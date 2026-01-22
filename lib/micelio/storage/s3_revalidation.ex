defmodule Micelio.Storage.S3Revalidation do
  @moduledoc false

  require Logger

  alias Micelio.Repo
  alias Micelio.Storage.S3Config

  def run do
    validator = validator_module()
    configs = Repo.all(S3Config)
    now = DateTime.utc_now()

    Enum.each(configs, fn config ->
      case validator.validate(config) do
        {:ok, result} ->
          update_config(config, %{validated_at: now, last_error: nil})

        {:error, result} ->
          message = error_message(result)
          update_config(config, %{validated_at: nil, last_error: message})
      end
    end)

    :ok
  end

  defp update_config(%S3Config{} = config, attrs) do
    changeset = Ecto.Changeset.change(config, attrs)

    case Repo.update(changeset) do
      {:ok, _updated} ->
        :ok

      {:error, changeset} ->
        Logger.warning("storage.s3_revalidation update_failed=#{inspect(changeset.errors)}")
        :error
    end
  end

  defp error_message(%{errors: errors}) when is_list(errors) do
    errors
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> truncate()
  end

  defp error_message(result), do: truncate(inspect(result))

  defp truncate(message) when is_binary(message), do: String.slice(message, 0, 500)

  defp validator_module do
    Application.get_env(:micelio, __MODULE__, [])
    |> Keyword.get(:validator, Micelio.Storage.S3Validator)
  end
end
