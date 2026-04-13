# Go "Hello World" Example

This example is the small default demo that backs the root `make example` target, using the repository's top-level `Dockerfile` and `config/project.cfg` configuration model.

## Usage

From the repository root, exercise the bundled example with the checked-in `config/project.cfg`:

```sh
PROJECT_CFG_FILE=config/project.cfg make example
```

The shorter `make example` path uses the same config file by default.
