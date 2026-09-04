defmodule IronEye.MixProject do
  use Mix.Project

  @version "1.0.0"

  def project do
    [
      app: :ironeye,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Official Elixir client for the IronEye document intelligence and collection API.",
      package: package(),
      docs: [main: "IronEye", source_url: "https://ironeye.org"]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Direct Softworks"],
      licenses: ["MIT"],
      links: %{
        "Documentation" => "https://ironeye.org/docs/sdk/elixir",
        "GitHub" => "https://github.com/IronEyeAPI/ironeye-elixir"
      }
    ]
  end
end
