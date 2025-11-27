defmodule Gust.Flows.SecretTest do
  use ExUnit.Case, async: true
  alias Gust.Flows.Secret

  describe "name format validation" do
    test "accepts valid names" do
      valid_names = ["MY_SECRET", "HELLO_WORLD", "SECRET_123"]

      for name <- valid_names do
        changeset = Secret.changeset(%Secret{}, %{name: name, value: "abc", value_type: :string})

        assert changeset.valid?, """
        Expected #{name} to be valid, but got errors: #{inspect(changeset.errors)}
        """
      end
    end

    test "rejects invalid names with correct error message" do
      invalid_names = [
        {"my_secret", "must be uppercase with underscores"},
        {"MySecret", "must be uppercase with underscores"},
        {"MY-SECRET", "must be uppercase with underscores"},
        {"MY SECRET", "must be uppercase with underscores"},
        {"", "can't be blank"}
      ]

      for {name, expected_msg} <- invalid_names do
        changeset = Secret.changeset(%Secret{}, %{name: name, value: "abc", value_type: :string})
        refute changeset.valid?, "Expected #{inspect(name)} to be invalid"

        {field, {msg, opts}} = hd(changeset.errors)

        assert field == :name
        assert msg == expected_msg

        if expected_msg == "must be uppercase with underscores" do
          assert opts[:validation] == :format
        end
      end
    end
  end

  describe "required fields" do
    test "rejects missing required fields" do
      changeset = Secret.changeset(%Secret{}, %{})
      refute changeset.valid?
      assert Keyword.keys(changeset.errors) == [:name, :value, :value_type]
    end
  end

  describe "JSON value validation" do
    test "accepts valid JSON when value_type is :json" do
      json_value = ~s({"foo": "bar"})

      changeset =
        Secret.changeset(%Secret{}, %{name: "VALID_JSON", value: json_value, value_type: :json})

      assert changeset.valid?, "Expected valid JSON to be accepted"
    end

    test "rejects invalid JSON when value_type is :json" do
      invalid_json = ~s({foo: bar})

      changeset =
        Secret.changeset(%Secret{}, %{
          name: "INVALID_JSON",
          value: invalid_json,
          value_type: :json
        })

      refute changeset.valid?
      assert {:value, {"must be valid JSON", []}} = hd(changeset.errors)
    end

    test "rejects nil JSON value" do
      changeset =
        Secret.changeset(%Secret{}, %{name: "EMPTY_JSON", value: nil, value_type: :json})

      refute changeset.valid?
      assert {:value, {"it cannot be empty", []}} = hd(changeset.errors)
    end
  end
end
