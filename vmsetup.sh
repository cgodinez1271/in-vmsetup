#!/bin/bash -e
#Thu Dec  4 12:39:16 EST 2014
#Carlos A. Godinez, Principal Engineer
#carlos_godinez@timeinc.com
#set -x

#
# MANUAL EXECUTION: vmutil myip; vmutil sshkeys
#

[ "$#" -eq 2 ] || { echo "Usage: $0 site-name release"; exit; }
SITE=$1
REL=$2
res1=$(date +%s.%N)

# validate site
if [[ ! `vmutil list | grep "$SITE"` ]] ; then
	echo -e "\n*** SITE NOT AVAILABLE ***\n"
	vmutil list
	exit 1
fi

echo -e "Host git.timeinc.net\n\tStrictHostKeyChecking no\n\tUserKnownHostsFile /dev/null\n" >> ~/.ssh/config
chmod 600 ~/.ssh/config

# validate release
if [[ ! `git ls-remote --tags git@git.timeinc.net:/dcms/reference 2>/dev/null | egrep "$REL$"` ]] ; then
	echo -e "\n*** RELEASE NOT AVAILABLE ***\n"
	git ls-remote --tags git@git.timeinc.net:/dcms/reference 2>/dev/null | perl -lne 'm!refs/tags/(release-v[\d.]+)$! && print $1'
	exit 1
fi

echo -e "\n>>> BUILDING SITE $SITE -> $REL <<<\n"

sudo bash -c "rm -rf /home/devadmin/dcms/$SITE" > /dev/null 2>&1 || true
echo 'y' | vmutil build $SITE || true

cd ~/dcms/$SITE
git clone git@git.timeinc.net:/dcms/reference
cd ~/dcms/$SITE/reference
git checkout $REL

cd ~/dcms/$SITE
git clone git@github.com:/TimeInc/dcms-site-$SITE.git src

vmutil build $SITE

echo -e "\n>>> DRUPAL INSTANCE BUILD <<<\n"

cd ~/dcms/$SITE
DB=$(perl -lne 'print $1 if /^\s+.database. => .(\w+_local).,/' /data/timeinc/content/local/$SITE/runtime/settings.php 2>/dev/null)
echo "Drupal database -> $DB"
echo "drop database if exists $DB" | mysql --user=devadmin --password=devadmin
drush -y si standard --account-name=devadmin --account-pass=devadmin --db-url='mysql://devadmin:devadmin@localhost/in_local'

echo -e "\n>>> CONFIGURING SOLR SEARCH FUNCTIONALITY <<<\n"

export TI_ENV=local
cd ~/dcms/$SITE
if ! drush pmi ti_search_config 2>&1 | grep 'not found' ; then
echo -e "Installing expect ..."
sudo bash -c 'yum -y install expect' > /dev/null 2>&1

/usr/bin/expect -c'
set timeout 120
#exp_internal 1
#log_user 1
spawn drush en ti_search_config
expect "Do you really want to continue? (y/n):" { send y\r }
#expect -re " \\\[(\[0-9]*)\\\] *:  '$SITE'" { set option $expect_out(1,string); send $option\r }
expect {
	-ex "ti_search_config disabled" { puts "*** ti_search_config enable FAILED ***"; exit 1 }
	-ex "command terminated abnormally" { puts "*** ti_search_config enable FAILED ***"; exit 1 }
	-ex "The Search API module was installed" { puts "*** ti_search_config was enabled successfully ***" }
}
'
else
	echo "Script does not support this release. Manual installation is required."
	sudo bash -c "rm -rf /home/devadmin/dcms/$SITE" > /dev/null 2>&1
	exit 1
fi

echo -e "\n>>> ENABLING MODULES AND THEMES WITH THE MASTER MODULE <<<\n"

# post deploy steps
phing -f reference/build.xml post-deploy-master 
phing -f reference/build.xml post-deploy-all 

# enable themes
cd ~/dcms/$SITE/site
drush en -y ti_editorial ti_editorial_mobile

# rebuild permissions
drush php-eval 'node_access_rebuild();'

# webserver permissions
chmod 777 ~/dcms/$SITE/site/sites/default/files

echo -e "\n>>> DONE CONFIGURING DEVELOPER SETUP <<<\n"

res2=$(date +%s.%N)
dt=$(echo "$res2 - $res1" | bc)
dd=$(echo "$dt/86400" | bc)
dt2=$(echo "$dt-86400*$dd" | bc)
dh=$(echo "$dt2/3600" | bc)
dt3=$(echo "$dt2-3600*$dh" | bc)
dm=$(echo "$dt3/60" | bc)
ds=$(echo "$dt3-60*$dm" | bc)

printf "Total runtime: %d:%02d:%02d:%02.4f\n" $dd $dh $dm $ds 
exit 0
