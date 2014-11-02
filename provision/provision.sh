#!/bin/bash
#
# provision.sh
#
# This file is specified in Vagrantfile and is loaded by Vagrant as the primary
# provisioning script whenever the commands `vagrant up`, `vagrant provision`,
# or `vagrant reload` are used. It provides all of the default packages and
# configurations included with Varying Vagrant Vagrants.

# By storing the date now, we can calculate the duration of provisioning at the
# end of this script.
start_seconds="$(date +%s)"

# Capture a basic ping result to Google's primary DNS server to determine if
# outside access is available to us. If this does not reply after 2 attempts,
# we try one of Level3's DNS servers as well. If neither IP replies to a ping,
# then we'll skip a few things further in provisioning rather than creating a
# bunch of errors.
ping_result="$(ping -c 2 8.8.4.4 2>&1)"
if [[ $ping_result != *bytes?from* ]]; then
    ping_result="$(ping -c 2 4.2.2.2 2>&1)"
fi

# PACKAGE INSTALLATION
#
# Build a bash array to pass all of the packages we want to install to a single
# apt-get command. This avoids doing all the leg work each time a package is
# set to install. It also allows us to easily comment out or add single
# packages. We set the array as empty to begin with so that we can append
# individual packages to it as required.
apt_package_install_list=()

# Start with a bash array containing all packages we want to install in the
# virtual machine. We'll then loop through each of these and check individual
# status before adding them to the apt_package_install_list array.
apt_package_check_list=(

    # nginx is installed as the default web server
    nginx

    # memcached is made available for object caching
    memcached

    # other packages that come in handy
    imagemagick
    git-core
    zip
    unzip
    ngrep
    curl
    make
    vim
    colordiff
    postfix
    zsh

    # Req'd for i18n tools
    gettext

    # Req'd for Webgrind
    graphviz

    # dos2unix
    # Allows conversion of DOS style line endings to something we'll have less
    # trouble with in Linux.
    dos2unix

    # nodejs
    g++
    nodejs

    #docker
    lxc-docker
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

# Postfix
#
# Use debconf-set-selections to specify the selections in the postfix setup. Set
# up as an 'Internet Site' with the host name 'tesla'. Note that if your current
# Internet connection does not allow communication over port 25, you will not be
# able to send mail, even with postfix installed.
echo postfix postfix/main_mailer_type select Internet Site | debconf-set-selections
echo postfix postfix/mailname string tesla | debconf-set-selections

# # Provide our custom apt sources before running `apt-get update`
ln -sf /srv/config/apt-source-append.list /etc/apt/sources.list.d/vvv-sources.list

# # Add docker repository
if [[ "$(docker --version)" ]]; then
    echo "Docker alredy installed"
else
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
    sh -c "echo deb https://get.docker.com/ubuntu docker main\
    > /etc/apt/sources.list.d/docker.list"
    echo "Linked docker apt sources"
fi

# # Add nodejs repository
if [[ "$(nodejs --version)" ]]; then
    echo "Nodejs alredy installed"
else
    curl -sL https://deb.nodesource.com/setup | bash -
    echo "Added nodejs source list"
fi


if [[ $ping_result == *bytes?from* ]]; then
    # If there are any packages to be installed in the apt_package_list array,
    # then we'll run `apt-get update` and then `apt-get install` to proceed.
    if [[ ${#apt_package_install_list[@]} = 0 ]]; then
        echo -e "No apt packages to install.\n"
    else
        # Before running `apt-get update`, we should add the public keys for
        # the packages that we are installing from non standard sources via
        # our appended apt source.list

        # Nginx.org nginx key ABF5BD827BD9BF62
        gpg -q --keyserver keyserver.ubuntu.com --recv-key ABF5BD827BD9BF62
        gpg -q -a --export ABF5BD827BD9BF62 | apt-key add -

        # Docker key


        # update all of the package references before installing anything
        echo "Running apt-get update..."
        apt-get update --assume-yes

        # install required packages
        echo "Installing apt-get packages..."
        apt-get install --assume-yes ${apt_package_install_list[@]}

        # Clean up apt caches
        apt-get clean
    fi

    # Make sure we have the latest npm version
    npm install -g npm

    # ack-grep
    #
    # Install ack-rep directory from the version hosted at beyondgrep.com as the
    # PPAs for Ubuntu Precise are not available yet.
    if [[ -f /usr/bin/ack ]]; then
        echo "ack-grep already installed"
    else
        echo "Installing ack-grep as ack"
        curl -s http://beyondgrep.com/ack-2.04-single-file > /usr/bin/ack && chmod +x /usr/bin/ack
    fi

else
    echo -e "\nNo network connection available, skipping package installation"
fi

# Configuration for nginx
if [[ ! -e /etc/nginx/server.key ]]; then
    echo "Generate Nginx server private key..."
    vvvgenrsa="$(openssl genrsa -out /etc/nginx/server.key 2048 2>&1)"
    echo $vvvgenrsa
fi
if [[ ! -e /etc/nginx/server.csr ]]; then
    echo "Generate Certificate Signing Request (CSR)..."
    openssl req -new -batch -key /etc/nginx/server.key -out /etc/nginx/server.csr
fi
if [[ ! -e /etc/nginx/server.crt ]]; then
    echo "Sign the certificate using the above private key and CSR..."
    vvvsigncert="$(openssl x509 -req -days 365 -in /etc/nginx/server.csr -signkey /etc/nginx/server.key -out /etc/nginx/server.crt 2>&1)"
    echo $vvvsigncert
fi

echo -e "\nSetup configuration files..."

# # Used to to ensure proper services are started on `vagrant up`
cp /srv/config/init/vvv-start.conf /etc/init/tesla-start.conf

echo " * /srv/config/init/tesla-start.conf               -> /etc/init/tesla-start.conf"

# # Copy nginx configuration from local
cp /srv/config/nginx-config/nginx.conf /etc/nginx/nginx.conf
if [[ ! -d /etc/nginx/custom-sites ]]; then
    mkdir /etc/nginx/custom-sites/
fi
rsync -rvzh --delete /srv/config/nginx-config/sites/ /etc/nginx/custom-sites/

echo " * /srv/config/nginx-config/nginx.conf           -> /etc/nginx/nginx.conf"
echo " * /srv/config/nginx-config/sites/               -> /etc/nginx/custom-sites"

# # Copy memcached configuration from local
cp /srv/config/memcached-config/memcached.conf /etc/memcached.conf

echo " * /srv/config/memcached-config/memcached.conf   -> /etc/memcached.conf"

# # Install prezto zsh

git clone --recursive https://github.com/sorin-ionescu/prezto.git "/home/vagrant/.zprezto"

echo '#!/bin/zsh
setopt EXTENDED_GLOB
for rcfile in /home/vagrant/.zprezto/runcoms/^README.md(.N); do
  ln -s "$rcfile" "/home/vagrant/.${rcfile:t}"
done
chsh -s $(which zsh) vagrant' | /bin/zsh


# RESTART SERVICES
#
# Make sure the services we expect to be running are running.
echo -e "\nRestart services..."
service nginx restart
service memcached restart


# Parse any tesla-hosts file located in www/ or subdirectories of www/
# for domains to be added to the virtual machine's host file so that it is
# self aware.
#
# Domains should be entered on new lines.
echo "Cleaning the virtual machine's /etc/hosts file..."
sed -n '/# tesla-auto$/!p' /etc/hosts > /tmp/hosts
mv /tmp/hosts /etc/hosts
echo "Adding domains to the virtual machine's /etc/hosts file..."
find /srv/www/ -maxdepth 5 -name 'tesla-hosts' | \
while read hostfile; do
    while IFS='' read -r line || [ -n "$line" ]; do
        if [[ "#" != ${line:0:1} ]]; then
            if [[ -z "$(grep -q "^127.0.0.1 $line$" /etc/hosts)" ]]; then
                echo "127.0.0.1 $line # tesla-auto" >> /etc/hosts
                echo " * Added $line from $hostfile"
            fi
        fi
    done < $hostfile
done

end_seconds="$(date +%s)"
echo "-----------------------------"
echo "Provisioning complete in "$(expr $end_seconds - $start_seconds)" seconds"
if [[ $ping_result == *bytes?from* ]]; then
    echo "External network connection established, packages up to date."
else
    echo "No external network available. Package installation and maintenance skipped."
fi
echo "For further setup instructions, visit http://vvv.dev"
