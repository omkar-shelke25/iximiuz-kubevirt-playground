
#!/bin/sh
# gh-release-dl.sh <owner/repo> <tag> <asset-name> <output-file>
#
# Downloads a GitHub release asset through the REST API. The
# github.com/<repo>/releases/download/... endpoint can return 504 for
# anonymous clients while the API asset endpoint keeps working, so the API is
# tried first and the plain download URL is only a fallback.
#
# If the build secret github_token is mounted, API calls are authenticated,
# which avoids the 60 requests per hour limit on shared CI runner IPs.
# curl does not forward the token when the API redirects to the file CDN.
set -eu

repo="$1"
tag="$2"
name="$3"
out="$4"

auth=""
if [ -s /run/secrets/github_token ]; then
  auth="Authorization: Bearer $(cat /run/secrets/github_token)"
fi

# fetch <retries> <curl args...>
fetch() {
  tries="$1"
  shift
  curl -fsSL --retry "$tries" --retry-all-errors --retry-delay 10 \
    --connect-timeout 30 --max-time 300 ${auth:+-H "$auth"} "$@"
}

echo "downloading ${repo} ${tag} ${name}"

# A rate-limited lookup returns 403, which retrying does not fix, so it fails fast.
id=""
if release=$(fetch 2 "https://api.github.com/repos/${repo}/releases/tags/${tag}"); then
  id=$(printf '%s' "$release" | jq -r --arg n "$name" '.assets[] | select(.name == $n) | .id')
fi

if [ -n "$id" ]; then
  fetch 10 -H 'Accept: application/octet-stream' -o "$out" \
    "https://api.github.com/repos/${repo}/releases/assets/${id}"
else
  echo "API lookup failed for ${name}, using the release download URL" >&2
  fetch 10 -o "$out" "https://github.com/${repo}/releases/download/${tag}/${name}"
fi

test -s "$out"
