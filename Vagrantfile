$script = <<-SCRIPT
    sudo apt-get update
    sudo apt-get -y install \
        curl \
        docker.io \
        docker-compose \
        git

    sudo systemctl start docker
    sudo systemctl enable docker

    wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.2/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install v12.16.0 2>/dev/null
    nvm install v10.19.0 2>/dev/null

    ssh-keyscan -H github.com >> ~/.ssh/known_hosts

    if [ ! -d 'application' ]; then
        git clone git@github.com:flashbackzoo/divvy-application.git /home/vagrant/application
    fi

    if [ ! -d 'api' ]; then
        git clone git@github.com:flashbackzoo/divvy-api.git /home/vagrant/api
    fi

    if [ ! -d 'chaincode' ]; then
        git clone git@github.com:flashbackzoo/divvy-chaincode.git /home/vagrant/chaincode
    fi

    if [ ! -d 'network' ]; then
        git clone git@github.com:flashbackzoo/divvy-network.git /home/vagrant/network
    fi

    cd /home/vagrant/network
    ./bootstrap.sh
    rm -rf ./config

    cd /home/vagrant/api
    sudo docker build -t trinsiclabs/divvy-api .

    cd /home/vagrant/api/src
    npm install --silent

    cd /home/vagrant/application/client
    npm install --silent

    cd /home/vagrant/chaincode
    npm install --silent
SCRIPT

Vagrant.configure("2") do |config|
    config.vm.box = "ubuntu/bionic64"

    config.vm.define "divvy"

    config.vm.provider "virtualbox" do |v|
        v.memory = 2048
        v.cpus = 2
    end

    config.ssh.forward_agent = true

    config.vm.network "private_network", type: "dhcp"

    config.vm.provision "shell", privileged: false, inline: $script
end
