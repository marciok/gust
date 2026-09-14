# Configuration example for Git-based DAG source
#
# To use this configuration:
# 1. Add to your mix.exs dependencies:
#    {:egit, "~> 0.3"}
#
# 2. Run: mix deps.get
#
# 3. Update repository URL and authentication method below
#
# 4. Run with:
#    MIX_ENV=dev mix phx.server
#
# 5. Or source this config by adding to config/config.exs:
#    import_config "git.exs"

import Config

# Basic configuration without authentication (public repository)
config :gust, dag_source: Gust.DAG.Source.Git

config :gust,
  dag_source:
    {Gust.DAG.Source.Git,
     url: System.get_env("GIT_REPO_URL", "https://github.com/user/dags.git"),
     branch: System.get_env("GIT_BRANCH", "main"),
     path: System.get_env("GIT_DAG_PATH", "/tmp/gust-dags-repo"),
     poll_seconds: String.to_integer(System.get_env("GIT_POLL_SECONDS", "30"))}

# ============================================
# Authentication Examples (uncomment one)
# ============================================

# Example 1: SSH Key Authentication with passphrase
# Ensure private key file has correct permissions (600)
# config :gust, dag_source: {Gust.DAG.Source.Git,
#   url: "git@github.com:user/dags.git",
#   credentials: [
#     type: :ssh_key,
#     username: "git",
#     privkey_path: "/home/app/.ssh/id_rsa",
#     pubkey_path: "/home/app/.ssh/id_rsa.pub",
#     passphrase: System.get_env("SSH_KEY_PASSPHRASE", "")
#   ]
# }

# Example 2: SSH Key with embedded PEM content
# config :gust, dag_source: {Gust.DAG.Source.Git,
#   url: "git@github.com:user/dags.git",
#   credentials: [
#     type: :ssh_key,
#     username: "git",
#     privkey: File.read!("/path/to/private_key"),
#     pubkey: File.read!("/path/to/public_key"),
#     passphrase: System.get_env("SSH_KEY_PASSPHRASE", "")
#   ]
# }

# Example 3: Username/Password (basic HTTP auth)
# config :gust, dag_source: {Gust.DAG.Source.Git,
#   url: "https://github.com/user/dags.git",
#   credentials: [
#     type: :userpass,
#     username: System.get_env("GIT_USERNAME"),
#     password: System.get_env("GIT_PASSWORD")
#   ]
# }

# Example 4: Personal Access Token (GitHub, GitLab, Gitea, etc.)
# Recommended: Use environment variable for token (not in config)
# config :gust, dag_source: {Gust.DAG.Source.Git,
#   url: "https://github.com/user/dags.git",
#   credentials: [
#     type: :token,
#     username: System.get_env("GIT_USERNAME", "git"),
#     token: System.get_env("GIT_TOKEN")
#   ]
# }

# Example 5: SSH Agent (uses system SSH agent)
# Useful for development or systems with SSH agent running
# config :gust, dag_source: {Gust.DAG.Source.Git,
#   url: "git@github.com:user/dags.git",
#   credentials: [
#     type: :ssh_agent,
#     username: "git"
#   ]
# }

# ============================================
# Environment Variables Reference
# ============================================
#
# Basic Configuration:
#   GIT_REPO_URL - Repository URL (required)
#   GIT_BRANCH - Branch to check out (default: "main")
#   GIT_DAG_PATH - Local cache path (default: /tmp/gust-dags-repo)
#   GIT_POLL_SECONDS - Polling interval (default: 30)
#
# Credentials (when using credentials):
#   GIT_CREDENTIALS_USERNAME - Username for userpass/token
#   GIT_CREDENTIALS_PASSWORD - Password for userpass, or token for :token type
#   SSH_KEY_PASSPHRASE - Passphrase for SSH keys
#
# ============================================
# Usage Examples
# ============================================
#
# 1. Public Repository (no credentials):
#    export GIT_REPO_URL="https://github.com/company/public-dags.git"
#    MIX_ENV=prod mix phx.server
#
# 2. Private SSH Repository:
#    export GIT_REPO_URL="git@github.com:company/private-dags.git"
#    export SSH_KEY_PASSPHRASE="my-key-passphrase"
#    MIX_ENV=prod mix phx.server
#    (Update config to use :ssh_key credentials type)
#
# 3. Private HTTPS with Token:
#    export GIT_REPO_URL="https://github.com/company/private-dags.git"
#    export GIT_USERNAME="my-username"
#    export GIT_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
#    MIX_ENV=prod mix phx.server
#    (Update config to use :token credentials type)
