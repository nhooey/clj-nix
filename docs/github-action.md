# GitHub Action

You can add a GitHub Action to automatically update the `deps-lock.json` file
when dependencies change:

```yaml
name: "Update deps-lock.json"
on:
  push:
    paths:
      - "**/deps.edn"

jobs:
  update-lock:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v7

      - uses: cachix/install-nix-action@v31

      - name: Update deps-lock
        run: "nix run github:jlesquembre/clj-nix#deps-lock"

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v8
        with:
          commit-message: Update deps-lock.json
          title: Update deps-lock.json
          branch: update-deps-lock
```

!!! note

    Check for newer versions of these actions, or let
    [Dependabot](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot)
    keep them up to date:

    - [actions/checkout](https://github.com/actions/checkout)
    - [cachix/install-nix-action](https://github.com/cachix/install-nix-action)
    - [peter-evans/create-pull-request](https://github.com/peter-evans/create-pull-request)
