#!/bin/sh
# Reject commits outside the Voc authorship allowlist.
#
# Two vectors have rewritten public history here, so both are
# blocked: a wrong author/committer identity (an agent default, a
# fresh machine without the noreply address), and a foreign
# Co-authored-by trailer in the message (agents append their own).
# The pre-push hook runs this on every push, and CI runs it on
# every push and pull request.
#
# Usage: check-authors.sh <rev-list-args>...
# Example: check-authors.sh origin/main..HEAD
set -u

allowed_name='vocino'
allowed_email='65593+vocino@users.noreply.github.com'

# One rev-list invocation: extra args are rev-list flags, so a new
# branch passes its tip as ("$tip" --not --all) and only genuinely
# new commits are checked.
revs=$(git rev-list "$@" 2>/dev/null) || {
  echo "check-authors: cannot resolve range '$*'" >&2
  exit 1
}

bad=0
for rev in $revs; do
  line=$(git log -1 --format='%H %an %ae %cn %ce' "$rev")
  # shellcheck disable=SC2086
  set -- $line
  sha=$1 an=$2 ae=$3 cn=$4 ce=$5
  if [ "$an" != "$allowed_name" ] || [ "$ae" != "$allowed_email" ] \
      || [ "$cn" != "$allowed_name" ] || [ "$ce" != "$allowed_email" ]; then
    echo "check-authors: $sha author '$an <$ae>' committer '$cn <$ce>'" >&2
    bad=$((bad + 1))
  fi
  trailers=$(git log -1 --format='%B' "$rev" | grep -i '^co-authored-by:' || true)
  if [ -n "$trailers" ]; then
    echo "check-authors: $sha carries foreign trailers:" >&2
    echo "$trailers" | sed 's/^/check-authors:   /' >&2
    bad=$((bad + 1))
  fi
done

if [ "$bad" -ne 0 ]; then
  echo "check-authors: $bad commit(s) outside the allowlist ($allowed_name <$allowed_email>, no foreign trailers)" >&2
  echo "check-authors: fix with 'git commit --amend --author=\"$allowed_name <$allowed_email>\"' and drop the trailer (then push), never by rewriting public history" >&2
  exit 1
fi
