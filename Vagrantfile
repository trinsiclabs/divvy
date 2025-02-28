$script = <<-SHELL
    sudo apt-get update
    sudo apt-get -y install \
        build-essential \
        curl \
        docker.io \
        docker-compose \
        git \
        software-properties-common \
        unzip

    sudo systemctl start docker
    sudo systemctl enable docker

    # Install PHP so we can use Composer.
    sudo add-apt-repository ppa:ondrej/php
    sudo apt-get update
    sudo apt-get -y install \
        php7.3-cli \
        php7.3-curl \
        php7.3-intl \
        php7.3-mbstring \
        php7.3-xml

    # Install Composer.
    HASH=8a6138e2a05a8c28539c9f0fb361159823655d7ad2deecb371b04a83966c61223adc522b0189079e3e9e277cd72b8897
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    php -r "if (hash_file('sha384', 'composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
    sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php

    wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.2/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install v10.19.0 2>/dev/null
    nvm install v12.16.0 2>/dev/null
    nvm alias default v12.16.0

    ssh-keyscan -H github.com >> ~/.ssh/known_hosts

    if [ ! -d 'application' ]; then
        git clone git@github.com:trinsiclabs/divvy-application.git /home/vagrant/application
    fi

    if [ ! -d 'api' ]; then
        git clone git@github.com:trinsiclabs/divvy-api.git /home/vagrant/api
    fi

    if [ ! -d 'chaincode' ]; then
        git clone git@github.com:trinsiclabs/divvy-chaincode.git /home/vagrant/chaincode
    fi

    if [ ! -d 'network' ]; then
        git clone git@github.com:trinsiclabs/divvy-network.git /home/vagrant/network
    fi

    # Pull the Fabric images and binaries.
    cd /home/vagrant/network
    ./bootstrap.sh
    rm -rf ./config

    # Pull and build the application images.
    sudo docker pull php:7.3.6-apache
    sudo docker pull mysql:5.7.29
    sudo docker pull schickling/mailcatcher
    sudo docker pull alpine:3.10
    cd /home/vagrant/application
    sudo docker-compose build
    cd /home/vagrant

    # Pull the API images
    sudo docker pull node:12.16.0

    cd /home/vagrant/api/src
    nvm use
    npm install --silent

    cd /home/vagrant/application/client
    nvm use
    npm install --silent

    cd /home/vagrant/chaincode/src
    nvm use
    npm install --silent

    nvm use default

    # Create a named pipe so containers can execute commands on the host.
    if [ ! -p /home/vagrant/host_queue ]; then
        mkfifo -m 0600 /home/vagrant/host_queue
    fi
SHELL

Vagrant.configure("2") do |config|
    config.vm.box = "ubuntu/bionic64"

    config.vm.define "divvy"

    config.vm.provider "virtualbox" do |v|
        v.memory = 4096
        v.cpus = 2
    end

    config.ssh.forward_agent = true

    config.vm.network "private_network", type: "dhcp"

    # Provision SSH key to enable pushing code to GitHub.
    config.vm.provision "shell" do |s|
        ssh_prv_key = ""
        ssh_pub_key = ""

        if File.file?("#{Dir.home}/.ssh/id_rsa")
            ssh_prv_key = File.read("#{Dir.home}/.ssh/id_rsa")
            ssh_pub_key = File.readlines("#{Dir.home}/.ssh/id_rsa.pub").first.strip
        else
            puts "No SSH key found. You will need to remedy this before pushing to the repository."
        end

        s.inline = <<-SHELL
            if grep -sq "#{ssh_pub_key}" /home/vagrant/.ssh/authorized_keys; then
                echo "SSH keys already provisioned."
                exit 0;
            fi

            echo "SSH key provisioning..."
            mkdir -p /home/vagrant/.ssh/
            touch /home/vagrant/.ssh/authorized_keys
            echo #{ssh_pub_key} >> /home/vagrant/.ssh/authorized_keys
            echo #{ssh_pub_key} > /home/vagrant/.ssh/id_rsa.pub
            chmod 644 /home/vagrant/.ssh/id_rsa.pub
            echo "#{ssh_prv_key}" > /home/vagrant/.ssh/id_rsa
            chmod 600 /home/vagrant/.ssh/id_rsa
            chown -R vagrant:vagrant /home/vagrant
            exit 0
        SHELL
    end

    config.vm.provision "file", source: "~/.gitconfig", destination: ".gitconfig"

    config.vm.provision "shell", privileged: false, inline: $script
end
