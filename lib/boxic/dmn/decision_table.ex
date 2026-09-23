defmodule Boxic.DMN.DecisionTable do
  @moduledoc false
  alias Boxic.DMN.FEEL
  alias Boxic.DMN.Model.DecisionTable

  @hit_policy_atoms %{
    "UNIQUE" => :unique,
    "FIRST" => :first,
    "ANY" => :any,
    "PRIORITY" => :priority,
    "RULE_ORDER" => :rule_order,
    "OUTPUT_ORDER" => :output_order,
    "COLLECT" => :collect
  }

  @spec evaluate(DecisionTable.t(), map()) :: {:ok, term()} | {:error, term()}
  def evaluate(%DecisionTable{} = table, context) do
    case evaluate_with_trace(table, context) do
      {:ok, value, _trace} -> {:ok, value}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Evaluates the table and, alongside the value, reports the decision-table
  rules that matched the inputs and the hit policy that reduced them.

  The returned trace is `%{matched_rules: [rule_id], hit_policy: atom}`. When
  no rule matches and default outputs apply, `matched_rules` is empty.
  """
  @spec evaluate_with_trace(DecisionTable.t(), map()) ::
          {:ok, term(), %{matched_rules: [term()], hit_policy: atom() | nil}}
          | {:error, term()}
  def evaluate_with_trace(%DecisionTable{} = table, context) do
    with {:ok, input_values} <- evaluate_table_inputs(table.inputs, context),
         {:ok, matches} <- matching_rules(table.rules, input_values, context),
         {:ok, results} <- evaluate_matched_outputs(matches, table.outputs, context) do
      reduce_hit_policy(table, matches, results, context)
    end
  end

  defp evaluate_matched_outputs(rules, outputs, context) do
    Enum.reduce_while(rules, {:ok, []}, fn rule, {:ok, values} ->
      case evaluate_rule_outputs(rule, outputs, context) do
        {:ok, value} -> {:cont, {:ok, values ++ [value]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp reduce_hit_policy(table, _rules, [], context)
       when table.hit_policy in ~w(UNIQUE FIRST ANY PRIORITY COLLECT) do
    case evaluate_default_outputs(table.outputs, context) do
      {:ok, value} -> {:ok, value, trace(table, [])}
      {:error, _reason} = error -> error
    end
  end

  defp reduce_hit_policy(%DecisionTable{hit_policy: "UNIQUE"} = table, rules, results, _context) do
    case results do
      [result] -> {:ok, result, trace(table, rules)}
      _ -> {:error, {:unique_hit_policy_violation, Enum.map(rules, & &1.id)}}
    end
  end

  defp reduce_hit_policy(
         %DecisionTable{hit_policy: "FIRST"} = table,
         rules,
         [result | _],
         _context
       ),
       do: {:ok, result, trace(table, rules)}

  defp reduce_hit_policy(
         %DecisionTable{hit_policy: "ANY"} = table,
         rules,
         [result | rest],
         _context
       ) do
    if Enum.all?(rest, &(&1 == result)) do
      {:ok, result, trace(table, rules)}
    else
      {:error, {:any_hit_policy_violation, Enum.map(rules, & &1.id)}}
    end
  end

  defp reduce_hit_policy(
         %DecisionTable{hit_policy: "RULE_ORDER"} = table,
         rules,
         results,
         _context
       ),
       do: {:ok, results, trace(table, rules)}

  defp reduce_hit_policy(
         %DecisionTable{hit_policy: "COLLECT", aggregation: nil} = table,
         rules,
         results,
         _context
       ),
       do: {:ok, results, trace(table, rules)}

  defp reduce_hit_policy(
         %DecisionTable{hit_policy: "COLLECT", aggregation: aggregation} = table,
         rules,
         results,
         _context
       ) do
    case aggregate_collect(aggregation, results) do
      {:ok, value} -> {:ok, value, trace(table, rules)}
      {:error, _reason} = error -> error
    end
  end

  defp reduce_hit_policy(%DecisionTable{hit_policy: policy} = table, rules, results, context)
       when policy in ~w(PRIORITY OUTPUT_ORDER) do
    with {:ok, ordered} <- order_by_priority(table, results, context) do
      if policy == "PRIORITY",
        do: {:ok, List.first(ordered), trace(table, rules)},
        else: {:ok, ordered, trace(table, rules)}
    end
  end

  defp trace(%DecisionTable{hit_policy: hit_policy}, rules) do
    %{
      matched_rules: rules |> Enum.map(& &1.id) |> Enum.reject(&is_nil/1),
      hit_policy: hit_policy_atom(hit_policy)
    }
  end

  defp hit_policy_atom(policy) when is_binary(policy),
    do: Map.get(@hit_policy_atoms, policy) || String.to_atom(String.downcase(policy))

  defp hit_policy_atom(_policy), do: nil

  defp aggregate_collect("COUNT", results), do: {:ok, Decimal.new(length(results))}
  defp aggregate_collect(_aggregation, []), do: {:ok, nil}

  defp aggregate_collect("SUM", results) do
    if Enum.all?(results, &match?(%Decimal{}, &1)),
      do: {:ok, Enum.reduce(results, Decimal.new(0), &Decimal.add/2)},
      else: {:error, :collect_aggregation_requires_numbers}
  end

  defp aggregate_collect(aggregation, results) when aggregation in ~w(MIN MAX) do
    if Enum.all?(results, &match?(%Decimal{}, &1)) do
      chooser =
        case aggregation do
          "MIN" ->
            fn value, current ->
              if Decimal.compare(value, current) == :lt, do: value, else: current
            end

          "MAX" ->
            fn value, current ->
              if Decimal.compare(value, current) == :gt, do: value, else: current
            end
        end

      {:ok, Enum.reduce(results, chooser)}
    else
      {:error, :collect_aggregation_requires_numbers}
    end
  end

  defp order_by_priority(%DecisionTable{outputs: [priority_output | _]}, results, context) do
    with values when is_binary(values) <- priority_output.allowed_values,
         {:ok, priorities} <- evaluate_priority_values(values, context),
         ranked <- Enum.map(results, &rank_result(&1, priority_output, priorities)),
         true <- Enum.all?(ranked, &match?({rank, _} when is_integer(rank), &1)) do
      {:ok, ranked |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))}
    else
      nil -> {:error, :missing_output_priorities}
      false -> {:error, :output_not_in_priority_values}
      {:error, _reason} = error -> error
    end
  end

  defp evaluate_priority_values(values, context) do
    {expression, bindings} = FEEL.normalize_names("[#{values}]", context)

    case Boxic.FEEL.evaluate(expression, bindings) do
      {:ok, priorities} when is_list(priorities) -> {:ok, priorities}
      {:ok, _value} -> {:error, :invalid_output_priorities}
      error -> error
    end
  end

  defp rank_result(result, output, priorities) do
    value =
      if is_map(result),
        do: Map.get(result, output.name || output.label),
        else: result

    {Enum.find_index(priorities, &(&1 == value)), result}
  end

  defp evaluate_table_inputs(inputs, context) do
    Enum.reduce_while(inputs, {:ok, []}, fn input, {:ok, values} ->
      {expression, bindings} = FEEL.normalize_names(input.expression, context)

      case Boxic.FEEL.evaluate(expression, bindings) do
        {:ok, value} -> {:cont, {:ok, values ++ [value]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp matching_rules(rules, input_values, context) do
    Enum.reduce_while(rules, {:ok, []}, fn rule, {:ok, matches} ->
      case rule_matches?(rule, input_values, context) do
        {:ok, true} -> {:cont, {:ok, matches ++ [rule]}}
        {:ok, false} -> {:cont, {:ok, matches}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp rule_matches?(rule, input_values, context) do
    Enum.zip(rule.input_entries, input_values)
    |> Enum.reduce_while({:ok, true}, fn {test, value}, {:ok, true} ->
      case evaluate_unary_tests(test, value, context) do
        {:ok, true} -> {:cont, {:ok, true}}
        {:ok, false} -> {:halt, {:ok, false}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp evaluate_unary_tests(text, value, context) do
    {text, context} = FEEL.normalize_names(text, context)

    text
    |> split_unary_tests()
    |> Enum.reduce_while({:ok, false}, fn test, {:ok, false} ->
      case Boxic.FEEL.evaluate_unary_test(test, value, context) do
        {:ok, true} -> {:halt, {:ok, true}}
        {:ok, false} -> {:cont, {:ok, false}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp split_unary_tests(text) do
    Regex.split(~r/,(?=(?:[^"]*"[^"]*")*[^"]*$)/, text, trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp evaluate_rule_outputs(rule, outputs, context) do
    with {:ok, values} <- evaluate_output_entries(rule.output_entries, context) do
      shape_output(outputs, values)
    end
  end

  defp evaluate_default_outputs(outputs, context) do
    defaults = Enum.map(outputs, & &1.default_output)

    if Enum.all?(defaults, &is_binary/1) do
      with {:ok, values} <- evaluate_output_entries(defaults, context),
           do: shape_output(outputs, values)
    else
      {:ok, nil}
    end
  end

  defp evaluate_output_entries(entries, context) do
    Enum.reduce_while(entries, {:ok, []}, fn expression, {:ok, values} ->
      {expression, bindings} = FEEL.normalize_names(expression, context)

      case Boxic.FEEL.evaluate(expression, bindings) do
        {:ok, value} -> {:cont, {:ok, values ++ [value]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp shape_output([_output], [value]), do: {:ok, value}

  defp shape_output(outputs, values) do
    names = Enum.map(outputs, &(&1.name || &1.label))

    if Enum.all?(names, &is_binary/1),
      do: {:ok, names |> Enum.zip(values) |> Map.new()},
      else: {:error, :unnamed_multiple_outputs}
  end

  # FEEL names may contain spaces and reserved words. The dependency graph gives
  # us the exact declared names, so compile those names to unambiguous evaluator
  # bindings before parsing the literal expression.
end
