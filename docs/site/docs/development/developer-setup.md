# Developer Setup

## Prerequisites

| Tool | Version | Purpose |
| --- | --- | --- |
| Ruby | 3.3+ | Build and test |
| Bundler | Latest | Dependency management |
| git | Latest | Version control |
| Docker | Latest | Local MQ containers (integration tests) |

## Required repositories

mq-rest-admin depends on two sibling repositories:

| Repository | Purpose |
| --- | --- |
| [mq-rest-admin-ruby](https://github.com/mq-rest-admin-project/mq-rest-admin-ruby) | This project |
| [vergil-tooling](https://github.com/vergil-project/vergil-tooling) | Canonical project standards (referenced by `AGENTS.md` and git hooks) |
| [mq-rest-admin-dev-environment](https://github.com/mq-rest-admin-project/mq-rest-admin-dev-environment) | Dockerized MQ test infrastructure (local and CI) |

## Recommended directory layout

Clone all three repositories as siblings:

```text
~/dev/
├── mq-rest-admin-ruby/
├── vergil-tooling/
└── mq-rest-admin-dev-environment/
```

```bash
cd ~/dev
git clone https://github.com/mq-rest-admin-project/mq-rest-admin-ruby.git
git clone https://github.com/vergil-project/vergil-tooling.git
git clone https://github.com/mq-rest-admin-project/mq-rest-admin-dev-environment.git
```

## Installing dependencies

```bash
bundle install
```

## Testing

```bash
bundle exec rake test              # Run all unit tests
bundle exec rake test TESTOPTS=-v  # Verbose output
```

Coverage is enforced at 100% line and branch via SimpleCov.

## Linting

```bash
bundle exec rubocop                # Check style
bundle exec rubocop -A             # Auto-fix
```

## Building the gem

```bash
gem build mq-rest-admin.gemspec
```

## Claude Code hook guard

The `.claude/hooks/guard.sh` PreToolUse hook blocks raw `git` and
`gh` commands in AI agent sessions — all operations must go through
the `vrg-git` / `vrg-gh` wrappers.

## Documentation

### Local setup

```bash
# Set up shared fragments symlink
scripts/dev/docs-setup.sh

# Install MkDocs
pip install mkdocs-material

# Build the documentation site
mkdocs build -f docs/site/mkdocs.yml

# Serve locally with live reload
mkdocs serve -f docs/site/mkdocs.yml
```
