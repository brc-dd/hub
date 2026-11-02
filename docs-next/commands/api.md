---
title: hub api
description: Make an authenticated GitHub API request (gh api).
kind: gh command
original: https://hub.github.com/hub-api.1.html
---

# hub api

`hub api` makes an authenticated request to the GitHub REST or GraphQL API and
prints the response. It runs `gh api` of the GitHub CLI (gh) with every
argument unchanged and in order, so gh's options, output and messages apply.
Use it for anything that hub and gh have no command for. The most common use is
a GET request on an endpoint of the current repository, where gh fills in
`{owner}` and `{repo}`.

```sh
hub api 'repos/{owner}/{repo}/releases' --jq '.[0].tag_name'
# => gh api repos/\{owner\}/\{repo\}/releases --jq .\[0\].tag_name
```

## Usage

```text
hub api ENDPOINT [GH-API-ARGS...]
```

`ENDPOINT` is a REST path such as `repos/rails/rails`, or `graphql`. gh fills
`{owner}`, `{repo}` and `{branch}` from the current repository. `GH-API-ARGS`
are gh api's options, in any position. `gh api --help` describes them.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md), `git api`
is the same command. Each `# =>` line is what `hub --noop` prints: the gh
command that hub runs. `hub --noop` quotes each argument for the shell, so `{`,
`[`, spaces and `!` appear with a backslash.

Get your own user record:

```sh
hub api user
# => gh api user
```

Select one value from the response with a jq query:

```sh
hub api repos/rails/rails --jq .stargazers_count
# => gh api repos/rails/rails --jq .stargazers_count
```

Comment on issue 23 of the current repository. A `KEY=VALUE` field from `-f`
or `-F` switches the method to `POST`. `-f` sends the value as a string:

```sh
hub api 'repos/{owner}/{repo}/issues/23/comments' -f 'body=Nice job!'
# => gh api repos/\{owner\}/\{repo\}/issues/23/comments -f body=Nice\ job\!
```

Read a field's value from a file with `-F` and `@FILE`:

```sh
hub api 'repos/{owner}/{repo}/issues/123/comments' -F body=@mycomment.txt
# => gh api repos/\{owner\}/\{repo\}/issues/123/comments -F body=@mycomment.txt
```

Run a GraphQL query from a file:

```sh
hub api graphql -F query=@myquery.graphql
# => gh api graphql -F query=@myquery.graphql
```

Send a request body from standard input. hub gives gh its standard input:

```sh
echo '{"query":"{viewer{login}}"}' | hub api graphql --input -
# => gh api graphql --input -
```

Send fields as a query string with `-X GET`. hub keeps a quoted word with
spaces as one argument:

```sh
hub api -X GET search/issues -f q='repo:cli/cli is:open'
# => gh api -X GET search/issues -f q=repo:cli/cli\ is:open
```

Fetch every page of a list. gh prints each page as a separate JSON document.
`--slurp` wraps them in one array:

```sh
hub api --paginate --slurp 'repos/{owner}/{repo}/issues'
# => gh api --paginate --slurp repos/\{owner\}/\{repo\}/issues
```

Cache a response for ten minutes. gh's `--cache` takes a duration with its
unit:

```sh
hub api --cache 600s 'repos/{owner}/{repo}'
# => gh api --cache 600s repos/\{owner\}/\{repo\}
```

Print the response status line and headers with the body:

```sh
hub api -i user
# => gh api -i user
```

Delete the branch `old-topic` on GitHub:

```sh
hub api -X DELETE 'repos/{owner}/{repo}/git/refs/heads/old-topic'
# => gh api -X DELETE repos/\{owner\}/\{repo\}/git/refs/heads/old-topic
```

Query a GitHub Enterprise host. The placeholders do not change the host, so
name it:

```sh
hub api --hostname ghe.example.com graphql -F query=@q.graphql
# => gh api --hostname ghe.example.com graphql -F query=@q.graphql
```

Keep using the original hub's `GITHUB_HOST`. hub passes it to gh as `GH_HOST`:

```sh
GITHUB_HOST=ghe.example.com hub api user
# => gh api user
```

Ask gh for its own help. `--help` after the first argument is gh's:

```sh
hub api user --help
# => gh api user --help
```

## Options

hub has no options of its own here. `-h` or `--help` as the first argument
prints hub's manual. The table gives the original hub's options in gh's
spelling.

| Original hub | gh's spelling | What it does |
|---|---|---|
| `-X`, `--method METHOD` | Same. | Set the HTTP method. Default: `GET`, or `POST` when you pass a field. |
| `-F`, `--field KEY=VALUE` | Same. | Add a typed field. `@FILE` reads the value from a file and `@-` from standard input. |
| `-f`, `--raw-field KEY=VALUE` | Same. | Add a field whose value is always a string. |
| `--input FILE` | Same. | Send the file as the request body. `-` reads standard input. |
| `-H`, `--header KEY:VALUE` | Same. | Add a request header. |
| `-i`, `--include` | Same. | Print the response status line and headers with the body. |
| `--paginate` | Same. | Fetch every page. Add `--slurp` for one JSON array. |
| `-t`, `--flat` | Not supported. | gh's `-t` is `--template`. Shape the output with `--jq`. |
| `--cache TTL` | `--cache 600s` | Cache the response. gh's duration needs its unit: `--cache 600` becomes `--cache 600s`. |
| `--obey-ratelimit` | Not supported. | gh has no such option. |
| `--color[=WHEN]` | Not supported. | gh colors JSON on a terminal. |

Every other argument goes to `gh api` unchanged. All of
[gh api's options](https://cli.github.com/manual/gh_api) work.

## How it works

hub applies these rules in order:

1. If the first argument is `-h` or `--help`, hub prints its manual, the same
   text as `hub help api`, and does not run gh.
2. Otherwise hub runs `gh api` with every argument unchanged and in order. This
   includes `--`, empty words, words with spaces, and `--help` or `-h` in any
   later position. `hub api -- --help` goes to gh as `gh api -- --help`.
3. hub adds no host and no repository. gh picks the host: `--hostname HOST`,
   else `GH_HOST`, else the one host gh is logged in to, else github.com.
4. If you set `GITHUB_HOST` (the original hub's variable) and not `GH_HOST`,
   hub passes `GITHUB_HOST` to gh as `GH_HOST`. `GH_HOST` wins when both are
   set.
5. gh fills `{owner}`, `{repo}` and `{branch}` from the current repository. They
   do not change the host. On GitHub Enterprise, add `--hostname`.
6. With `hub --noop api`, hub prints the `gh api` command and does not run it.
   This holds for every method, `GET` included.

gh writes the response to standard output and its messages to standard error.
If you run `hub api` without arguments, gh prints its own usage error. See
[Hosts and login](../guide/hosts-and-login.md) for how gh logs in to a host.

## Exit status

`hub api` exits with gh's status. For example, if gh prints
`gh: Not Found (HTTP 404)` on standard error and exits with a nonzero status,
hub exits with that same status. To test for success in a script, check `$?`
after `hub api`.

hub needs gh 2.55 or newer, logged in. Without gh, hub prints this message and
exits with status 1:

```text
hub api: this command needs the GitHub CLI, gh (https://cli.github.com)
```

## Differences from the original hub

| Original hub | This hub |
|---|---|
| hub sent the request itself. | gh makes the request: `gh api` with the arguments unchanged. Output and messages are gh's. |
| `-X`, `-F`, `-f`, `--input`, `-H`, `-i` and `--paginate` worked. | Same. |
| `-t`, `--flat` printed `path<TAB>value` lines. | Not supported. `-t` is gh's `--template`. Use `--jq`. |
| `--cache TTL` in seconds, for example `--cache 600`. | `--cache` needs a unit: `--cache 600s`. |
| `--obey-ratelimit` waited for the rate limit to reset and retried. | Not supported. |
| `--color[=WHEN]` set when to color the output. | Not supported. gh colors JSON on a terminal. |
| `--paginate` printed several JSON documents. | gh does the same. Add `--slurp` for one array. |
| A response other than 2xx exited with status 22. | Exits with gh's status. |
| `{owner}` and `{repo}` came from the git remote. | gh fills `{owner}`, `{repo}` and also `{branch}`. |
| `GITHUB_HOST` chose the host. | `GITHUB_HOST` reaches gh as `GH_HOST` when `GH_HOST` is not set. `--hostname` names a host for one call. |

## See also

- [hub gist](gist.md), [hub issue](issue.md), [hub pr](pr.md) and
  [hub release](release.md): the other gh commands.
- [Hosts and login](../guide/hosts-and-login.md) and
  [Configuration](../guide/configuration.md): hosts, login and the variables
  hub reads.
- [hub and gh](../compatibility/hub-vs-gh.md): what hub hands to gh.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual: [hub-api(1)](https://hub.github.com/hub-api.1.html)
- gh's manual: [gh api](https://cli.github.com/manual/gh_api) for every option,
  and [gh help formatting](https://cli.github.com/manual/gh_help_formatting) for
  `--jq` and `--template`.
- This hub's manual: [hub api](https://brc-dd.github.io/hub/api.html)
