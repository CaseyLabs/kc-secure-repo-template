# Go "Hello World" Example

This example is the small default demo that backs the root `make example` target, using the repository's top-level `Dockerfile` and `project.env` configuration model.

## Usage

From the repository root, exercise the bundled example without creating a local `project.env` first:

```sh
PROJECT_ENV=project.env.example make example
```

After you copy `project.env.example` to `project.env`, the shorter `make example` path works too.
