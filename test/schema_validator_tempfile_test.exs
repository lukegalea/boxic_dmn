defmodule Boxic.DMN.XML.SchemaValidatorTempFileTest do
  # async: false because the cleanup test inspects the shared temp directory for
  # this VM's files, which other async validation tests create concurrently.
  use ExUnit.Case, async: false

  alias Boxic.DMN.XML.SchemaValidator

  @xml ~s(<definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/" id="d" name="D" namespace="urn:d"/>)

  test "pre-existing files at old-style names do not break validation" do
    next = System.unique_integer([:positive, :monotonic]) + 1
    tmp = System.tmp_dir!()

    planted =
      for n <- next..(next + 200) do
        path = Path.join(tmp, "boxic-dmn-schema-#{n}.xml")
        File.write!(path, "planted")
        path
      end

    on_exit(fn -> Enum.each(planted, &File.rm/1) end)

    assert :ok = SchemaValidator.validate(@xml)
    assert Enum.all?(planted, &(File.read!(&1) == "planted"))
  end

  test "temp files are removed after validation" do
    pattern = Path.join(System.tmp_dir!(), "boxic-dmn-schema-#{System.pid()}-*")
    before = Path.wildcard(pattern)
    assert :ok = SchemaValidator.validate(@xml)
    assert {:error, _} = SchemaValidator.validate("<definitions/>")
    assert Path.wildcard(pattern) -- before == []
  end
end
