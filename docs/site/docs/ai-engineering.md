# AI Engineering

--8<-- "ai-engineering.md"

## Ruby-specific quality standards

- **Test coverage**: 100% line and branch coverage enforced via SimpleCov
- **Static analysis**: RuboCop with rubocop-minitest and rubocop-rake plugins
- **Zero runtime dependencies**: stdlib `net/http` only
- **Ruby version support**: tested against Ruby 3.3 and 3.4
