# Chat demo backend

## Local setup

Use the Ruby version pinned in `.ruby-version`, then install dependencies and prepare the local
database:

```sh
bin/setup
```

## Quality checks

The backend uses the same core toolchain as the maintained Ruby services:

```sh
bundle exec rspec                 # test suite
COVERAGE=1 bundle exec rspec      # test suite with SimpleCov report
bin/rubocop                       # Ruby and RSpec style checks
bin/brakeman --no-pager           # Rails static security scan
```

GitHub Actions runs these checks for pull requests and pushes to `main`.
