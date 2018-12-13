#!/bin/bash

set -exuo pipefail

BFGJAR="bfg-1.13.0.jar"

GW_SVN_REPO='svn://source2010.engineering.clearswift.org/gateways'
THIRDPARTY_SVN_REPO='svn://source2010.engineering.clearswift.org/thirdpartysource'
THIRDPARTY_DIR=thirdpartysource

function createCommit {

MSG=""

for prd in $1; do

    REF="${prd#branch:}"

    if [ "${prd}" != "$REF" ] ; then
	MSG+="Branching $REF\n"
    else 
	PROD=$( echo "$prd" | cut -f 1 -d '@' )
	VER=$( echo "$prd" | cut -f 2 -d '@' )

	MSG+="$PROD version $VER\n"
    fi
done



#git reset --soft master
#git checkout master
git add --all
git add .gitignore
git commit -m "$( echo "$MSG" | sed 's/\\n/\n/g' )"

for prd in $1; do

    REF="${prd#branch:}"

    if [ "${prd}" != "$REF" ] ; then
	git branch "$REF"
    else 
	PROD=$( echo "$prd" | cut -f 1 -d '@' )
	VER=$( echo "$prd" | cut -f 2 -d '@' )

	git tag "${PROD}/${VER}"
    fi
done


}

function preserveEmptyDirs {

find . -type d -empty | while read dir; do
    touch "$dir/.gitignore"
done

}

function createState {

BRANCH="${1/->*/}"

if [ -z "$BRANCH" -o "$BRANCH" = "$1" ] ; then
    BRANCH=master
fi

SVNREF=${1/*->/}

GWREF=${SVNREF/&*/}
TRDPREF=${SVNREF/*&/}

cd $GW_REPO
git reset --hard
git clean -fd
git checkout "$BRANCH"
git reset --hard

cd $WD
GW_TMP=$( basename "${GW_REPO}").tmp


if [ -d "$GW_TMP" ] ; then
    rm -rf "$GW_TMP"
fi


svn checkout "$GW_SVN_REPO/$GWREF" "$GW_TMP"
ln -s "$GW_REPO/.git" "$GW_TMP/.git"
rm -rf "$GW_TMP/.svn"

cd "$GW_TMP"
svn checkout "$THIRDPARTY_SVN_REPO/$TRDPREF" "$THIRDPARTY_DIR"
rm -rf "$THIRDPARTY_DIR/.svn"

find -type f -name .project -exec rm {} \;
find -type f -name .cproject -exec rm {} \;
find -type f -name .settings -exec rm -rf {} \;
find -type f -name .classpath -exec rm {} \;

cat <<END >>".gitignore"
**/.project
**/.cproject
**/.settings
**/.classpath
END

preserveEmptyDirs



createCommit "$2"

}

function moveTag {

COMMIT=$(git log "$1" --grep="$3" | grep commit | cut -f 2 -d ' ')

git tag -d "$2"
git tag "$2" "$COMMIT"


}


if [ $# -ne 2 ] ; then
    echo "Use: <gateways repo> <mapping file>"
    exit 1
fi


BFGJAR="$(realpath $BFGJAR)"

if [ ! -f $BFGJAR ] ; then
    echo "Can't find BFG jar: $BFGJAR"
    exit 1
fi

GW_REPO="$(realpath $1)"

WD=`pwd`

readarray COMMITS < "$2"

cd "${GW_REPO}"

#Creating new ROOT commit for all branches

MASTER_ROOT=$(git log master --max-parents=0 | grep commit | cut -f 2 -d ' ')

#To create a commit, we need a directory tree for it, so we create an empty one first:
tree=`git hash-object -wt tree --stdin < /dev/null`

#Now we can wrap a commit around it:
root_commit=`git commit-tree -m 'ROOT' $tree`

git filter-branch --parent-filter "sed 's/^\$/-p $root_commit/'" --tag-name-filter cat -- --all

# clean up
git checkout master

#And now we can rebase master onto that:
#git rebase --onto $root_commit $MASTER_ROOT


echo "Creating svn/trunk branch"

git branch svn/trunk && echo "Success"

echo "Resetting master to the root commit: $root_commit"

git update-ref refs/remotes/origin/master $root_commit &&
git reset --hard $root_commit


git branch -r | grep -v '\->' | grep -v 'origin/master' | while read remote; do
    LOCAL="${remote#origin/}"
    git branch --track "${LOCAL}" "$remote"; 

    FIRST_BRANCH_COMM=$(git log "$LOCAL" --max-parents=0 | grep commit | cut -f 2 -d ' ')

#    if [ $FIRST_BRANCH_COMM != $root_commit ] ; then
#	git rebase $root_commit "${LOCAL}"
#    fi
done

for cm in "${COMMITS[@]}" ; do


    REF=$( echo "$cm" | cut -f 1 -d '!' )
    PRODS=$( echo "$cm" | cut -f 2 -d '!' )
    PRODLST=$(  echo "$PRODS" | sed 's/,/ /g' )

    echo "Processing reference: ${REF} for products: ${PRODLST}"

    createState "$REF" "$PRODLST"

done

cd "$GW_REPO"

moveTag 'svn/trunk' 'svn/seg/4.1/RTM' 'MAIL-7378'
moveTag 'svn/trunk' 'svn/seg/4.2/RTM' 'MAIL-7598'
moveTag 'svn/trunk' 'svn/sig/4.2/RTM' 'MAIL-7598'
moveTag 'svn/release/4.3' 'svn/seg/4.3/RTM' 'WEB-4632'
moveTag 'svn/release/4.3' 'svn/sig/4.3/RTM' 'WEB-4632'
moveTag 'svn/release/4.3' 'svn/swg/4.3/RTM' 'WEB-4632'
moveTag 'svn/ert/Email421arch' 'svn/seg/4.2.1/RTM' 'Archiving branches'
moveTag 'svn/ert/Email421arch' 'svn/sig/4.2.1/RTM' 'Archiving branches'

#Renaming tags. Removing /RTM suffix
git tag  | grep RTM | while read tag 
do
    NORTM="${tag%/RTM}"
    TMPTAG="${NORTM}-t"
    git tag "${TMPTAG}" "${tag}"
    git tag -d "$tag"
    git tag "${NORTM}" "${TMPTAG}"
    git tag -d "${TMPTAG}"
done

#cd "$GW_REPO"
#git reset --hard master
#git checkout -b feature/dev/WebAtsHttps1
#createState 'branches/dev/WebAtsHttps1&trunk' 'SWG@DEV'

#cd "$GW_REPO"
#git reset --hard master
#git checkout -b branches/dev/devtoolset-7
#createState 'branches/dev/devtoolset-7_gateways&trunk' 'SEG@DEV'

#cd "$GW_REPO"
#git reset --hard master
#git checkout -b branches/dev/engine1811
#createState 'branches/dev/engine1811&trunk' 'SEG@DEV'



java -jar "$BFGJAR" -b 50M

git -c gc.reflogExpireUnreachable=0 -c gc.pruneExpire=now gc

