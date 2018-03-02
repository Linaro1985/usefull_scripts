#!/bin/sh
CURRENT_DIR=$PWD
echo "Repo scanning..."
REPO_LIST=$(repo forall -c "git count-objects -v | grep 'packs:' | grep -v 'packs: [0-1]' > /dev/null && pwd | uniq")
for repo_path in $REPO_LIST
do
    echo "Processing repo: "$repo_path
    cd $repo_path
    git gc
    echo ""
done
cd $CURRENT_DIR
echo "All done!"
