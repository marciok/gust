defmodule GustWeb.SecretLiveTest do
  use GustWeb.ConnCase

  import Phoenix.LiveViewTest
  import Gust.FlowsFixtures

  @create_attrs %{name: "SOME_SECRET", value: "some value", value_type: :string}
  @update_attrs %{name: "SOME_SECRET", value: "some updated value", value_type: :string}
  @invalid_attrs %{name: nil, value: nil}
  @invalid_json %{name: "SOME_SECRET", value: "invalid json value", value_type: :json}

  defp create_secret(_) do
    secret = secret_fixture()
    %{secret: secret}
  end

  describe "Index" do
    setup [:create_secret]

    test "lists all secrets", %{conn: conn, secret: secret} do
      {:ok, _index_live, html} = live(conn, ~p"/secrets")

      assert html =~ "Listing Secrets"
      assert html =~ secret.name
    end

    test "saves new secret", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/secrets")

      assert index_live |> element("a", "New Secret") |> render_click() =~
               "New Secret"

      assert_patch(index_live, ~p"/secrets/new")

      assert index_live
             |> form("#secret-form", secret: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#secret-form", secret: @invalid_json)
             |> render_change() =~ "must be valid JSON"

      assert index_live
             |> form("#secret-form", secret: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/secrets")

      html = render(index_live)
      assert html =~ "Secret created successfully"
      assert html =~ "SOME_NAME"
    end

    test "updates secret in listing", %{conn: conn, secret: secret} do
      {:ok, index_live, _html} = live(conn, ~p"/secrets")

      assert index_live |> element("#secrets-#{secret.id} a", "Edit") |> render_click() =~
               "Edit"

      assert_patch(index_live, ~p"/secrets/#{secret}/edit")

      secret_value_html = index_live |> element("#secret-form_value") |> render()

      case Regex.run(~r/<textarea[^>]*>(.*?)<\/textarea>/, secret_value_html) do
        [_, value] -> assert value == ""
      end

      assert index_live
             |> form("#secret-form", secret: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#secret-form", secret: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/secrets")

      html = render(index_live)
      assert html =~ "Secret updated successfully"
    end

    test "deletes secret in listing", %{conn: conn, secret: secret} do
      {:ok, index_live, _html} = live(conn, ~p"/secrets")

      assert index_live |> element("#secrets-#{secret.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#secrets-#{secret.id}")
    end
  end
end
