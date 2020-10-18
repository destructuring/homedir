SHELL := /bin/bash

.PHONY: docs

menu:
	@perl -ne 'printf("%10s: %s\n","$$1","$$2") if m{^([\w+-]+):[^#]+#\s(.+)$$}' Makefile

thing: # Upgrade all the things
	$(MAKE) update
	$(MAKE) update
	$(MAKE) install

update: # Update code
	git pull
	$(MAKE) update_inner
	source ./.bash_profile && $(MAKE) -f .dotfiles/Makefile upgrade

update_inner:
	if [[ ! -d .asdf/.git ]]; then git clone https://github.com/asdf-vm/asdf.git asdf; mv asdf/.git .asdf/; rm -rf asdf; cd .asdf && git reset --hard; fi
	git submodule update --init
	if [[ ! -d .dotfiles ]]; then git clone "$(shell cat .dotfiles-repo)" .dotfiles; fi
	cd .dotfiles && git pull && git submodule update --init
	$(MAKE) -f .dotfiles/Makefile update

upgrade: # Upgrade installed software
	brew upgrade
	if [[ "$(shell uname -s)" == "Linux" ]]; then brew upgrade --cask; fi

brew:
	 curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh | bash -

install-aws:
	sudo yum install -y jq htop
	sudo yum install -y expat-devel readline-devel openssl-devel bzip2-devel sqlite-devel
	/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
	cd .. && homedir/bin/install-homedir

setup-do:
	./env.sh $(MAKE) setup-do-inner

setup-do-inner:
	for s in /swap0 /swap1 /swap2 /swap3; do sudo fallocate -l 1G $$s; sudo chmod 0600 $$s; sudo mkswap $$s; sudo swapon $$s; done
	while ! test -e /dev/sda; do date; sleep 5; done
	sudo mount /dev/sda /mnt
	if test -d /mnt/zerotier-one; then sudo rm -rf /var/lib/zerotier-one; sudo rsync -ia /mnt/zerotier-one /var/lib/; fi
	sudo systemctl enable zerotier-one; sudo systemctl start zerotier-one
	sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
	sudo cat ~root/.ssh/authorized_keys > .ssh/authorized_keys
	chmod 700 .ssh; chmod 600 .ssh/authorized_keys
	ln -nfs /mnt/password-store .password-store
	ln -nfs /mnt/work work
	git pull && make setup-dummy setup-registry
	docker pull --quiet defn/home:home && docker tag defn/home:home localhost:5000/defn/home:home && docker push localhost:5000/defn/home:home
	git submodule sync
	git submodule update --init --recursive --remote
	-make thing

setup-aws:
	sudo perl -pe 's{^#\s*GatewayPorts .*}{GatewayPorts yes}' /etc/ssh/sshd_config | grep Gateway

setup-dummy:
	bin/setup-dummy

setup-registry:
	docker run -d -p 5000:5000 --restart=always --name registry registry:2

install: # Install software bundles
	source ./.bash_profile && ( $(MAKE) install_inner || true )
	-chmod 600 .ssh/config

install_inner:
	if test -w /usr/local/bin; then ln -nfs python3 /usr/local/bin/python; fi
	if test -w /home/linuxbrew/.linuxbrew/bin; then ln -nfs python3 /home/linuxbrew/.linuxbrew/bin/python; fi
	-if test -x "$(shell which brew)"; then brew bundle && rm -rf $(shell brew --cache) 2>/dev/null; fi
	source ./.bash_profile && asdf install
	if ! test -f venv/bin/activate; then rm -rf venv; source ./.bash_profile && python3 -m venv venv; fi
	bundle check || bundle install --path .vendor/bundle
	source venv/bin/activate && pip install --upgrade pip
	source venv/bin/activate && pip install --no-cache-dir -r requirements.txt
	if ! test -x "$(HOME)/bin/docker-credential-pass"; then go get github.com/jojomomojo/docker-credential-helpers/pass/cmd@v0.6.5; go build -o bin/docker-credential-pass github.com/jojomomojo/docker-credential-helpers/pass/cmd; fi
	mkdir -p "$(HOME)/.config/kustomize/plugin/goabout.com/v1beta1/sopssecretgenerator"
	if ! test -f "$(HOME)/.config/kustomize/plugin/goabout.com/v1beta1/sopssecretgenerator"; then curl -o "$(HOME)/.config/kustomize/plugin/goabout.com/v1beta1/sopssecretgenerator/SopsSecretGenerator" -sSL https://github.com/goabout/kustomize-sopssecretgenerator/releases/download/v1.3.2/SopsSecretGenerator_1.3.2_$(shell uname -s | tr '[:upper:]' '[:lower:]')_amd64; fi
	-chmod 755 "$(HOME)/.config/kustomize/plugin/goabout.com/v1beta1/sopssecretgenerator/SopsSecretGenerator"
	source ./.bash_profile && $(MAKE) -f .dotfiles/Makefile install
	rm -rf $(shell brew --cache) 2>/dev/null
	rm -f /home/linuxbrew/.linuxbrew/bin/perl

fmt: # Format with isort, black
	@echo
	drone exec --pipeline $@

lint: # Run drone lint
	@echo
	drone exec --pipeline $@

docs: # Build docs
	@echo
	drone exec --pipeline $@

requirements: # Compile requirements
	@echo
	drone exec --pipeline $@

test:
	 env PYTEST_ADDOPTS='--keep-cluster --cluster-name=test' pytest -v -s test.py
