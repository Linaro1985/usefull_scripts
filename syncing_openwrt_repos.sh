#!/bin/sh

sync_repo() {
	echo "Syncing repo: $1"
	pushd $1 >/dev/null
	git fetch upstream
	git remote update --prune
	BRANCH_LIST=$(git branch -r | grep 'upstream/' | sed 's/^.*upstream\///g')
	for branch in $BRANCH_LIST; do
		echo "Syncing branch: $branch"
		git checkout --track origin/$branch || git checkout $branch
		git merge upstream/$branch
	done
	git push origin --all
	git checkout master
	popd >/dev/null
}

sync_repo luci
sync_repo packages
sync_repo routing
sync_repo telephony
