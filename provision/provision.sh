#!/bin/bash

start_seconds="$(date +%s)"

if [[ "$(wget --tries=3 --timeout=5 --spider http://google.com 2>&1 | grep 'connected')" ]]; then
    echo "Network connection detected..."
    ping_result="Connected"
else
    echo "Network connection not detected. Unable to reach google.com..."
    ping_result="Not Connected"
fi

apt_package_install_list=()

apt_package_check_list=(
    nginx
    nodejs
    apt-transport-https
    lxc-docker
    vim
)

echo "Check for apt packages to install..."

# Loop through each of our packages that should be installed on the system. If
# not yet installed, it should be added to the array of packages to install.
for pkg in "${apt_package_check_list[@]}"; do
    package_version="$(dpkg -s $pkg 2>&1 | grep 'Version:' | cut -d " " -f 2)"
    if [[ -n "${package_version}" ]]; then
        space_count="$(expr 20 - "${#pkg}")" #11
        pack_space_count="$(expr 30 - "${#package_version}")"
        real_space="$(expr ${space_count} + ${pack_space_count} + ${#package_version})"
        printf " * $pkg %${real_space}.${#package_version}s ${package_version}\n"
    else
        echo " *" $pkg [not installed]
        apt_package_install_list+=($pkg)
    fi
done

ln -sf /srv/config/apt-source-append.list /etc/apt/sources.list.d/teslabox-sources.list
echo "Linked custom apt sources"

if [[ $ping_result == "Connected" ]]; then
    # If there are any packages to be installed in the apt_package_list array,
    # then we'll run `apt-get update` and then `apt-get install` to proceed.
    if [[ ${#apt_package_install_list[@]} = 0 ]]; then
        echo -e "No apt packages to install.\n"
    else
        # Before running `apt-get update`, we should add the public keys for
        # the packages that we are installing from non standard sources via
        # our appended apt source.list

        # Retrieve the Nginx signing key from nginx.org
        echo "Applying Nginx signing key..."
        wget --quiet http://nginx.org/keys/nginx_signing.key -O- | apt-key add -

        # Apply the nodejs assigning key
        echo "Applying nodejs signing key..."
        apt-key adv --quiet --keyserver hkp://keyserver.ubuntu.com:80 --recv-key C7917B12 2>&1 | grep "gpg:"
        apt-key export C7917B12 | apt-key add -


        # Apply the dockerjs assigning key
        sudo apt-key adv --quiet --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9

        # update all of the package references before installing anything
        echo "Running apt-get update..."
        apt-get update --assume-yes

        # install required packages
        echo "Installing apt-get packages..."
        apt-get install --assume-yes ${apt_package_install_list[@]}

        # Clean up apt caches
        apt-get clean
    fi

    # npm
    #
    # Make sure we have the latest npm version and the update checker module
    npm install -g npm
    npm install -g npm-check-updates
else
    echo -e "\nNo network connection available, skipping package installation"
fi

# Used to to ensure proper services are started on `vagrant up`
cp /srv/config/init/teslabox-start.conf /etc/init/teslabox-start.conf

echo " * Copied /srv/config/init/teslabox-start.conf               to /etc/init/teslabox-start.conf"

# # Copy nginx configuration from local
cp /srv/config/nginx-config/nginx.conf /etc/nginx/nginx.conf
if [[ ! -d /etc/nginx/custom-sites ]]; then
    mkdir /etc/nginx/custom-sites/
fi
rsync -rvzh --delete /srv/config/nginx-config/sites/ /etc/nginx/custom-sites/

echo " * /srv/config/nginx-config/nginx.conf           -> /etc/nginx/nginx.conf"
echo " * /srv/config/nginx-config/sites/               -> /etc/nginx/custom-sites"

service nginx restart

echo "Cleaning the virtual machine's /etc/hosts file..."
sed -n '/# auto$/!p' /etc/hosts > /tmp/hosts
mv /tmp/hosts /etc/hosts
echo "Adding domains to the virtual machine's /etc/hosts file..."
find /srv/www/ -maxdepth 5 -name 'hosts' | \
while read hostfile; do
    while IFS='' read -r line || [ -n "$line" ]; do
        if [[ "#" != ${line:0:1} ]]; then
            if [[ -z "$(grep -q "^127.0.1.1 $line$" /etc/hosts)" ]]; then
                echo "127.0.1.1 $line # auto" >> /etc/hosts
                echo " * Added $line from $hostfile"
            fi
        fi
    done < $hostfile
done

end_seconds="$(date +%s)"
echo "-----------------------------"
echo "Provisioning complete in "$(expr $end_seconds - $start_seconds)" seconds"
if [[ $ping_result == "Connected" ]]; then
    echo "External network connection established, packages up to date."
else
    echo "No external network available. Package installation and maintenance skipped."
fi
