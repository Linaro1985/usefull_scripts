#!/bin/bash

UBUNTU_EDITION="xenial"
UBUNTU_ROOT="ubuntu_root"
UBUNTU_PATH="/home/linaro/${UBUNTU_ROOT}"
UBUNTU_MIRROR="http://mirror.yandex.ru/ubuntu"

PROCESS_COUNT_FILE="/dev/shm/${UBUNTU_ROOT}.lock"

function change_proc_count() {
	local counter=0
	if [ -f ${PROCESS_COUNT_FILE} ];then
		counter=$(flock -x -w 10 ${PROCESS_COUNT_FILE} -c "cat ${PROCESS_COUNT_FILE}")
		if [ -z ${counter} ]; then
			counter=0
		fi
	fi
	{
		flock -x -w 10 3 || exit 1
		if [ $1 -eq 1 ]; then
			counter=$((counter + 1))
		else
			if [ counter != 0 ];then
				counter=$((counter - 1))
			fi
		fi
		echo $counter>&3
	} 3>${PROCESS_COUNT_FILE}
	if [ $counter -eq 0 ];then
		rm -f ${PROCESS_COUNT_FILE}
	fi
	echo $counter
}

function request_root() {
	if [ $EUID != 0 ]; then
		sudo "$0" "$@"
		exit $?
	fi
}

function clean_garbage() {
	rm -rf "${UBUNTU_PATH}/tmp/*"
}

function mount_points() {
	local UBUNTU_PROC="${UBUNTU_PATH}/proc"
	local UBUNTU_SYS="${UBUNTU_PATH}/sys"
	local UBUNTU_DEV="${UBUNTU_PATH}/dev"
	
	if [ $1 -eq 1 ]; then
		if ! mountpoint -q ${UBUNTU_PROC}; then
			mount -t proc /proc ${UBUNTU_PROC}
		fi
		if ! mountpoint -q ${UBUNTU_SYS}; then
			mount --rbind /sys ${UBUNTU_SYS}
			mount --make-rslave ${UBUNTU_SYS}
		fi
		if ! mountpoint -q ${UBUNTU_DEV}; then
			mount --rbind /dev ${UBUNTU_DEV}
			mount --make-rslave ${UBUNTU_DEV}
		fi
	else
		umount -R ${UBUNTU_DEV}
		umount -R ${UBUNTU_SYS}
		umount ${UBUNTU_PROC}
		clean_garbage
	fi
}

function run_chrooted_process() {
	chroot ${UBUNTU_PATH} /usr/bin/env -i \
		HOME=/root \
		TERM=$TERM \
		PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games" \
		PS1='\u:\w\$ ' \
		/bin/bash -c "source /etc/environment && source /etc/profile && source /etc/default/locale && export LANG && $1" --login +h
}

function update_apt_list() {
	local APT_PATH="${UBUNTU_PATH}/etc/apt"
	if [ ! -d ${APT_PATH} ]; then
		echo "Creating apt path"
		mkdir -p ${APT_PATH}
	fi

	echo "Create new apt list file"
	local APT_LIST_PATH="${APT_PATH}/sources.list"

	local BIN_TEMP="deb ${UBUNTU_MIRROR} ${UBUNTU_EDITION}"
	local SRC_TEMP="deb-src ${UBUNTU_MIRROR} ${UBUNTU_EDITION}"
	local REPOS="main restricted universe multiverse"

	echo "${BIN_TEMP} ${REPOS}" > $APT_LIST_PATH
	echo "${BIN_TEMP}-updates ${REPOS}" >> $APT_LIST_PATH
	echo "${BIN_TEMP}-backports ${REPOS}" >> $APT_LIST_PATH
	echo "${BIN_TEMP}-security ${REPOS}" >> $APT_LIST_PATH
	echo "${SRC_TEMP} ${REPOS}" >> $APT_LIST_PATH		
	echo "${SRC_TEMP}-updates ${REPOS}" >> $APT_LIST_PATH
	echo "${SRC_TEMP}-backports ${REPOS}" >> $APT_LIST_PATH
	echo "${SRC_TEMP}-security ${REPOS}" >> $APT_LIST_PATH

	run_chrooted_process "apt-get update && apt-get -y install dialog apt-utils && apt-get -y upgrade"
}

function install_locale() {
        # run_chrooted_process "apt-get -y install locales"
        sed -i 's/^# *\(en_US.UTF-8\)/\1/' ${DEBIAN_PATH}/etc/locale.gen
        run_chrooted_process "locale-gen"
}

function make_install() {
	echo "Installing Ubuntu base system to chroot"
	debootstrap --variant=buildd --arch amd64 ${UBUNTU_EDITION} ${UBUNTU_PATH} ${UBUNTU_MIRROR}

	echo "Configuring target system"
	
	echo "Coping hosts file"
	cp -vp /etc/hosts ${UBUNTU_PATH}/etc/hosts

	echo "Setting chroot name"
	echo "ubuntu" > ${UBUNTU_PATH}/etc/debian_chroot

	mount_points 1
	
	update_apt_list
	install_locale

	echo "Setup ccache"
	echo "max_size = 50.0G" > ${UBUNTU_PATH}/etc/ccache.conf
	echo "export PATH=\"/usr/lib/ccache/bin/:\$PATH\"" > ${UBUNTU_PATH}/etc/profile.d/ccache.sh
	chmod +x ${UBUNTU_PATH}/etc/profile.d/ccache.sh
	run_chrooted_process "apt-get -y install ccache"
}

request_root
change_proc_count 1 > /dev/null

# Make install if target root does not exists
if [ ! -d ${UBUNTU_PATH} ]; then
	mkdir ${UBUNTU_PATH}
	make_install
fi

mount_points 1
run_chrooted_process "/bin/bash"

if [ $(change_proc_count 0) -eq 0 ];then
	mount_points 0
fi
