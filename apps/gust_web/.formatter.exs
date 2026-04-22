[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"],
  locals_without_parens: [gust_dashboard: 1, gust_dashboard: 2],
  export: [
    locals_without_parens: [gust_dashboard: 1, gust_dashboard: 2]
  ]
]
