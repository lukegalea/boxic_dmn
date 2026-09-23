defmodule Boxic.DMN.EvaluateWithTraceTest do
  use ExUnit.Case, async: true

  defmodule ExternalHost do
    def max(left, right), do: Kernel.max(left, right)
  end

  defmodule ExternalRegistry do
    use Boxic.FEEL.ExternalFunctions

    external("max", {ExternalHost, :max},
      parameters: [:float, :float],
      returns: :number
    )
  end

  defp load!(xml) do
    assert {:ok, model} = Boxic.DMN.load_xml(xml)
    assert :ok = Boxic.DMN.validate(model)
    model
  end

  defp severity_table_xml(hit_policy, output_extras \\ "", variable_type \\ "string") do
    """
    <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
      id="defs" name="trace #{hit_policy}" namespace="urn:trace:#{String.downcase(String.replace(hit_policy, " ", "-"))}">
      <inputData id="severity" name="Severity">
        <variable id="severity_var" name="Severity" typeRef="number"/>
      </inputData>
      <decision id="triage" name="Triage">
        <variable id="triage_var" name="Triage" typeRef="#{variable_type}"/>
        <informationRequirement><requiredInput href="#severity"/></informationRequirement>
        <decisionTable id="triage_table" hitPolicy="#{hit_policy}">
          <input id="triage_input">
            <inputExpression typeRef="number"><text>Severity</text></inputExpression>
          </input>
          <output id="triage_output" name="value" typeRef="string">
            <outputValues><text>"emergency","urgent","routine"</text></outputValues>
            #{output_extras}
          </output>
          <rule id="rule_emergency">
            <inputEntry><text>&lt;= 1</text></inputEntry>
            <outputEntry><text>"emergency"</text></outputEntry>
          </rule>
          <rule id="rule_urgent">
            <inputEntry><text>&lt;= 2</text></inputEntry>
            <outputEntry><text>"urgent"</text></outputEntry>
          </rule>
          <rule id="rule_routine">
            <inputEntry><text>&lt;= 3</text></inputEntry>
            <outputEntry><text>"routine"</text></outputEntry>
          </rule>
        </decisionTable>
      </decision>
    </definitions>
    """
  end

  defp assert_value_parity(model, decision, context) do
    assert {:ok, expected} = Boxic.DMN.evaluate(model, decision, context)
    assert {:ok, ^expected, _trace} = Boxic.DMN.evaluate_with_trace(model, decision, context)
    expected
  end

  test "UNIQUE reports the single matching rule" do
    model =
      load!("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
        id="defs" name="trace unique" namespace="urn:trace:unique">
        <inputData id="age" name="Age">
          <variable id="age_var" name="Age" typeRef="number"/>
        </inputData>
        <decision id="classification" name="Classification">
          <variable id="classification_var" name="Classification" typeRef="string"/>
          <informationRequirement><requiredInput href="#age"/></informationRequirement>
          <decisionTable id="classification_table" hitPolicy="UNIQUE">
            <input id="age_input">
              <inputExpression typeRef="number"><text>Age</text></inputExpression>
            </input>
            <output id="classification_output" name="classification" typeRef="string"/>
            <rule id="adult_rule">
              <inputEntry><text>&gt;= 18</text></inputEntry>
              <outputEntry><text>"adult"</text></outputEntry>
            </rule>
            <rule id="minor_rule">
              <inputEntry><text>&lt; 18</text></inputEntry>
              <outputEntry><text>"minor"</text></outputEntry>
            </rule>
          </decisionTable>
        </decision>
      </definitions>
      """)

    assert "adult" = assert_value_parity(model, "Classification", %{"Age" => Decimal.new(30)})

    assert {:ok, "adult", %{matched_rules: ["adult_rule"], hit_policy: :unique}} =
             Boxic.DMN.evaluate_with_trace(model, "Classification", %{"Age" => Decimal.new(30)})

    assert {:ok, "minor", %{matched_rules: ["minor_rule"], hit_policy: :unique}} =
             Boxic.DMN.evaluate_with_trace(model, "Classification", %{"Age" => Decimal.new(7)})
  end

  test "FIRST reports every matching rule in table order while the value stays the first" do
    model = load!(severity_table_xml("FIRST"))

    assert "urgent" = assert_value_parity(model, "Triage", %{"Severity" => Decimal.new(2)})

    assert {:ok, "urgent", %{matched_rules: ["rule_urgent", "rule_routine"], hit_policy: :first}} =
             Boxic.DMN.evaluate_with_trace(model, "Triage", %{"Severity" => Decimal.new(2)})
  end

  test "ANY reports every matching rule when outputs agree" do
    model =
      load!("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
        id="defs" name="trace any" namespace="urn:trace:any">
        <inputData id="severity" name="Severity">
          <variable id="severity_var" name="Severity" typeRef="number"/>
        </inputData>
        <decision id="triage" name="Triage">
          <variable id="triage_var" name="Triage" typeRef="string"/>
          <informationRequirement><requiredInput href="#severity"/></informationRequirement>
          <decisionTable id="triage_table" hitPolicy="ANY">
            <input id="triage_input">
              <inputExpression typeRef="number"><text>Severity</text></inputExpression>
            </input>
            <output id="triage_output" name="value" typeRef="string"/>
            <rule id="rule_primary">
              <inputEntry><text>&lt;= 2</text></inputEntry>
              <outputEntry><text>"urgent"</text></outputEntry>
            </rule>
            <rule id="rule_agreeing">
              <inputEntry><text>&gt; 0</text></inputEntry>
              <outputEntry><text>"urgent"</text></outputEntry>
            </rule>
          </decisionTable>
        </decision>
      </definitions>
      """)

    assert "urgent" = assert_value_parity(model, "Triage", %{"Severity" => Decimal.new(2)})

    assert {:ok, "urgent", %{matched_rules: ["rule_primary", "rule_agreeing"], hit_policy: :any}} =
             Boxic.DMN.evaluate_with_trace(model, "Triage", %{"Severity" => Decimal.new(2)})
  end

  test "ANY violation errors still identify the conflicting rules" do
    model =
      load!("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
        id="defs" name="trace any violation" namespace="urn:trace:any-violation">
        <inputData id="severity" name="Severity">
          <variable id="severity_var" name="Severity" typeRef="number"/>
        </inputData>
        <decision id="triage" name="Triage">
          <variable id="triage_var" name="Triage" typeRef="string"/>
          <informationRequirement><requiredInput href="#severity"/></informationRequirement>
          <decisionTable id="triage_table" hitPolicy="ANY">
            <input id="triage_input">
              <inputExpression typeRef="number"><text>Severity</text></inputExpression>
            </input>
            <output id="triage_output" name="value" typeRef="string"/>
            <rule id="rule_calls_it_urgent">
              <inputEntry><text>&lt;= 3</text></inputEntry>
              <outputEntry><text>"urgent"</text></outputEntry>
            </rule>
            <rule id="rule_calls_it_routine">
              <inputEntry><text>&gt;= 2</text></inputEntry>
              <outputEntry><text>"routine"</text></outputEntry>
            </rule>
          </decisionTable>
        </decision>
      </definitions>
      """)

    assert {:error,
            {:any_hit_policy_violation, ["rule_calls_it_urgent", "rule_calls_it_routine"]}} =
             Boxic.DMN.evaluate_with_trace(model, "Triage", %{"Severity" => Decimal.new(2)})

    assert {:error,
            {:any_hit_policy_violation, ["rule_calls_it_urgent", "rule_calls_it_routine"]}} =
             Boxic.DMN.evaluate(model, "Triage", %{"Severity" => Decimal.new(2)})
  end

  test "PRIORITY reports every matching rule while the value is the highest-priority one" do
    model = load!(severity_table_xml("PRIORITY"))

    assert "urgent" = assert_value_parity(model, "Triage", %{"Severity" => Decimal.new(2)})

    assert {:ok, "urgent",
            %{matched_rules: ["rule_urgent", "rule_routine"], hit_policy: :priority}} =
             Boxic.DMN.evaluate_with_trace(model, "Triage", %{"Severity" => Decimal.new(2)})
  end

  test "RULE_ORDER and OUTPUT_ORDER report every matching rule and keep the ordered list value" do
    for {policy, atom} <- [{"RULE ORDER", :rule_order}, {"OUTPUT ORDER", :output_order}] do
      model = load!(severity_table_xml(policy, "", "Any"))

      assert ["urgent", "routine"] =
               assert_value_parity(model, "Triage", %{"Severity" => Decimal.new(2)})

      assert {:ok, ["urgent", "routine"], trace} =
               Boxic.DMN.evaluate_with_trace(model, "Triage", %{"Severity" => Decimal.new(2)})

      assert trace.matched_rules == ["rule_urgent", "rule_routine"]
      assert trace.hit_policy == atom
    end
  end

  test "COLLECT reports every matching rule for plain and aggregated results" do
    model = load!(severity_table_xml("COLLECT", "", "Any"))

    assert ["urgent", "routine"] =
             assert_value_parity(model, "Triage", %{"Severity" => Decimal.new(2)})

    assert {:ok, ["urgent", "routine"],
            %{matched_rules: ["rule_urgent", "rule_routine"], hit_policy: :collect}} =
             Boxic.DMN.evaluate_with_trace(model, "Triage", %{"Severity" => Decimal.new(2)})

    count_model =
      load!("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
        id="defs" name="trace collect count" namespace="urn:trace:collect-count">
        <inputData id="severity" name="Severity">
          <variable id="severity_var" name="Severity" typeRef="number"/>
        </inputData>
        <decision id="count" name="Count">
          <variable id="count_var" name="Count" typeRef="number"/>
          <informationRequirement><requiredInput href="#severity"/></informationRequirement>
          <decisionTable id="count_table" hitPolicy="COLLECT" aggregation="COUNT">
            <input id="count_input">
              <inputExpression typeRef="number"><text>Severity</text></inputExpression>
            </input>
            <output id="count_output" name="value" typeRef="string"/>
            <rule id="rule_urgent">
              <inputEntry><text>&lt;= 2</text></inputEntry>
              <outputEntry><text>"urgent"</text></outputEntry>
            </rule>
            <rule id="rule_routine">
              <inputEntry><text>&lt;= 3</text></inputEntry>
              <outputEntry><text>"routine"</text></outputEntry>
            </rule>
          </decisionTable>
        </decision>
      </definitions>
      """)

    assert Decimal.equal?(
             assert_value_parity(count_model, "Count", %{"Severity" => Decimal.new(2)}),
             Decimal.new(2)
           )

    assert {:ok, count, %{matched_rules: ["rule_urgent", "rule_routine"], hit_policy: :collect}} =
             Boxic.DMN.evaluate_with_trace(count_model, "Count", %{"Severity" => Decimal.new(2)})

    assert Decimal.equal?(count, Decimal.new(2))
  end

  test "no matching rule traces an empty matched_rules list with the table's hit policy" do
    default_output = ~s(<defaultOutputEntry><text>"routine"</text></defaultOutputEntry>)
    model = load!(severity_table_xml("PRIORITY", default_output))

    assert "routine" = assert_value_parity(model, "Triage", %{"Severity" => Decimal.new(9)})

    assert {:ok, "routine", %{matched_rules: [], hit_policy: :priority}} =
             Boxic.DMN.evaluate_with_trace(model, "Triage", %{"Severity" => Decimal.new(9)})
  end

  test "decisions whose expression is not a decision table trace an empty list and nil policy" do
    model =
      load!("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
        id="defs" name="trace literal" namespace="urn:trace:literal">
        <decision id="answer" name="Answer">
          <variable id="answer_var" name="Answer" typeRef="number"/>
          <literalExpression><text>40 + 2</text></literalExpression>
        </decision>
      </definitions>
      """)

    assert Decimal.equal?(assert_value_parity(model, "Answer", %{}), Decimal.new(42))

    assert {:ok, answer, %{matched_rules: [], hit_policy: nil}} =
             Boxic.DMN.evaluate_with_trace(model, "Answer")

    assert Decimal.equal?(answer, Decimal.new(42))
  end

  test "rules without ids are skipped in the trace without changing the value" do
    model =
      load!("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
        id="defs" name="trace idless" namespace="urn:trace:idless">
        <inputData id="severity" name="Severity">
          <variable id="severity_var" name="Severity" typeRef="number"/>
        </inputData>
        <decision id="triage" name="Triage">
          <variable id="triage_var" name="Triage" typeRef="string"/>
          <informationRequirement><requiredInput href="#severity"/></informationRequirement>
          <decisionTable id="triage_table" hitPolicy="UNIQUE">
            <input id="triage_input">
              <inputExpression typeRef="number"><text>Severity</text></inputExpression>
            </input>
            <output id="triage_output" name="value" typeRef="string"/>
            <rule>
              <inputEntry><text>&lt;= 3</text></inputEntry>
              <outputEntry><text>"routine"</text></outputEntry>
            </rule>
          </decisionTable>
        </decision>
      </definitions>
      """)

    assert "routine" = assert_value_parity(model, "Triage", %{"Severity" => Decimal.new(2)})

    assert {:ok, "routine", %{matched_rules: [], hit_policy: :unique}} =
             Boxic.DMN.evaluate_with_trace(model, "Triage", %{"Severity" => Decimal.new(2)})
  end

  test "decision dependencies keep memoized values and the trace of the requested decision" do
    model =
      load!("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
        id="defs" name="trace diamond" namespace="urn:trace:diamond">
        <decision id="base" name="Base">
          <variable id="base_var" name="Base" typeRef="number"/>
          <literalExpression><text>1</text></literalExpression>
        </decision>
        <decision id="left" name="Left">
          <variable id="left_var" name="Left" typeRef="number"/>
          <informationRequirement><requiredDecision href="#base"/></informationRequirement>
          <decisionTable id="left_table" hitPolicy="UNIQUE">
            <input id="left_input">
              <inputExpression typeRef="number"><text>Base</text></inputExpression>
            </input>
            <output id="left_output" name="value" typeRef="number"/>
            <rule id="left_rule">
              <inputEntry><text>-</text></inputEntry>
              <outputEntry><text>Base</text></outputEntry>
            </rule>
          </decisionTable>
        </decision>
        <decision id="right" name="Right">
          <variable id="right_var" name="Right" typeRef="number"/>
          <informationRequirement><requiredDecision href="#base"/></informationRequirement>
          <decisionTable id="right_table" hitPolicy="UNIQUE">
            <input id="right_input">
              <inputExpression typeRef="number"><text>Base</text></inputExpression>
            </input>
            <output id="right_output" name="value" typeRef="number"/>
            <rule id="right_rule">
              <inputEntry><text>-</text></inputEntry>
              <outputEntry><text>Base</text></outputEntry>
            </rule>
          </decisionTable>
        </decision>
        <decision id="total" name="Total">
          <variable id="total_var" name="Total" typeRef="number"/>
          <informationRequirement><requiredDecision href="#left"/></informationRequirement>
          <informationRequirement><requiredDecision href="#right"/></informationRequirement>
          <literalExpression><text>Left + Right</text></literalExpression>
        </decision>
      </definitions>
      """)

    assert {:ok, left, %{matched_rules: ["left_rule"], hit_policy: :unique}} =
             Boxic.DMN.evaluate_with_trace(model, "Left", %{})

    assert Decimal.equal?(left, Decimal.new(1))

    assert Decimal.equal?(assert_value_parity(model, "Total", %{}), Decimal.new(2))

    assert {:ok, total, %{matched_rules: [], hit_policy: nil}} =
             Boxic.DMN.evaluate_with_trace(model, "Total", %{})

    assert Decimal.equal?(total, Decimal.new(2))
  end

  test "evaluate_with_trace/4 accepts evaluator options" do
    model =
      load!("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
        id="defs" name="trace options" namespace="urn:trace:options">
        <decision id="decision" name="Decision">
          <literalExpression><text>max(123, 456)</text></literalExpression>
        </decision>
      </definitions>
      """)

    assert {:ok, value, %{matched_rules: [], hit_policy: nil}} =
             Boxic.DMN.evaluate_with_trace(model, "Decision", %{},
               external_functions: ExternalRegistry
             )

    assert Decimal.equal?(value, Decimal.new(456))
  end

  test "evaluation errors are identical between evaluate and evaluate_with_trace" do
    model =
      load!("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
        id="defs" name="trace unique violation" namespace="urn:trace:unique-violation">
        <inputData id="severity" name="Severity">
          <variable id="severity_var" name="Severity" typeRef="number"/>
        </inputData>
        <decision id="triage" name="Triage">
          <variable id="triage_var" name="Triage" typeRef="string"/>
          <informationRequirement><requiredInput href="#severity"/></informationRequirement>
          <decisionTable id="triage_table" hitPolicy="UNIQUE">
            <input id="triage_input">
              <inputExpression typeRef="number"><text>Severity</text></inputExpression>
            </input>
            <output id="triage_output" name="value" typeRef="string"/>
            <rule id="rule_urgent">
              <inputEntry><text>&lt;= 3</text></inputEntry>
              <outputEntry><text>"urgent"</text></outputEntry>
            </rule>
            <rule id="rule_routine">
              <inputEntry><text>&gt;= 2</text></inputEntry>
              <outputEntry><text>"routine"</text></outputEntry>
            </rule>
          </decisionTable>
        </decision>
      </definitions>
      """)

    assert {:error, {:unique_hit_policy_violation, ["rule_urgent", "rule_routine"]}} =
             Boxic.DMN.evaluate(model, "Triage", %{"Severity" => Decimal.new(2)})

    assert {:error, {:unique_hit_policy_violation, ["rule_urgent", "rule_routine"]}} =
             Boxic.DMN.evaluate_with_trace(model, "Triage", %{"Severity" => Decimal.new(2)})
  end
end
