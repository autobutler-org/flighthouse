# 0029. A gitignored hosts file maps backend hosts to sign-in credentials

- Status: Accepted
- Date: 2026-10-10

## Context

[ADR 0023](0023-web-runner-configuration.md) has the web runner build and serve the app itself, and gives a `type`
sign-in step one source for its value: the environment variable named in `valueFromEnv`. An app that signs into a
backend needs that backend's URL, a username, and a password. Running one config against a second backend means
exporting a different set of variables by hand, and nothing ties a username and password to the host they belong to.
[#122](https://github.com/autobutler-org/flighthouse/issues/122) asks for a map from host to credentials.

## Decision

### The hosts file

Credentials live in `.flighthouse/hosts.yaml`, resolved against the config file's directory like every other
relative path. The location is fixed and has no config key. The file is never committed: the quickstart already has
projects ignore `.flighthouse/`.

```yaml
hosts:
  https://app.example.com:
    username: flighthouse
    password: flighthouse
```

`hosts` is required and maps a host URL to exactly `username` and `password`, both non-empty strings. Any other key,
a missing key, or a value that is not a non-empty string is a failure that names the file and the dotted path, such
as `hosts.https://app.example.com.password`. A failure never includes a value read from the file.

### The step key

A `type` step may set `valueFromHost`, `valueFromEnv`, or both. At least one is required. `valueFromHost` is one of
`url`, `username`, or `password`: the selected entry's key, or one of its two fields.

```yaml
- type: type
  selector: 'input[aria-label="Password"]'
  valueFromHost: password
  valueFromEnv: FLIGHTHOUSE_PASSWORD
```

### Selecting a host

`collect --host <url>` selects the entry with that key. With no option, a hosts file that has exactly one entry
selects it. With no option and zero or several entries, no host is selected.

### Resolving a step's value

1. When a host is selected and the step sets `valueFromHost`, the host's value is used, even if `valueFromEnv` is
   also set.
2. Otherwise, when the step sets `valueFromEnv`, the environment variable is read. Missing or empty is the same
   failure as before.
3. Otherwise the step has only `valueFromHost` and no host is selected. That is a failure that says to pass `--host`
   and lists the hosts the file defines, or says the file is missing or defines none.

Every step is resolved before the browser touches the page, as environment variables are today.

### When the file is read

The hosts file is read only when `--host` was passed or some step sets `valueFromHost`. A config whose steps use only
`valueFromEnv` never touches it and behaves exactly as before, whatever the file contains.

- `--host` with no hosts file is a failure naming the file's path.
- `--host` naming a host with no entry is a failure naming that host and listing the ones defined.
- No file and no `--host` is not a failure by itself. Each step with a `valueFromEnv` fallback reads the environment,
  and a step without one fails by rule 3.

### Secrecy

A username or password from the file is passed only to the browser's typing action. It does not appear in a report,
a raw output flighthouse writes, a failure message, or a log line. Failures name host URLs, which are not secret.

## Consequences

- One committed config works locally with the hosts file and in CI with only environment variables, when its steps set
  both keys. CI can also write the file from its secret store before `collect`.
- A step that sets both keys has two sources. Which one applies depends on whether a host is selected, so a hosts file
  with exactly one entry changes where such a step's value comes from without any option.
- The file holds plain-text credentials on disk. It suits throwaway audit accounts. A project that will not keep a
  password on disk keeps using `valueFromEnv` alone.
- Nothing audits a remote origin. The host is a backend the locally served app signs into, and ADR 0023's "the runner
  builds and serves" stands.

## Alternatives considered

- **Environment variable names in the committed config**, a map from host to `usernameFromEnv` and `passwordFromEnv`:
  nothing secret on disk, but every host needs its own pair of variables exported, which is the chore this removes.
- **Credentials in `flighthouse.yaml`**: simplest, and anyone who commits the config publishes them.
- **A `web.auth.host` key instead of `--host`**: ties the committed config to one backend, so switching means
  editing it.
- **Exactly one of `valueFromHost` or `valueFromEnv` per step**: one source per step, but a config could not serve
  both a developer with the file and a CI job with only variables.
- **A config key for the file's path**: nobody asked for one, and a fixed path keeps the ignore rule simple.
