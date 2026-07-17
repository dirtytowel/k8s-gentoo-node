INVENTORY ?= inventory/vagrant.yml

.PHONY: venv kubeconfig stage4 box vagrant clean-vagrant clean-box-cache clean-box clean

venv:
	cd ansible && python3 -m venv .venv
	cd ansible && .venv/bin/pip install --no-cache-dir -r requirements.txt
	cd ansible && .venv/bin/ansible-galaxy collection install -r requirements.yml -p .venv/collections --force

kubeconfig:
	cd ansible && .venv/bin/ansible-playbook -i $(INVENTORY) playbooks/save-kubeconfig.yml

stage4:
	cd catalyst && docker compose run --rm --build catalyst

box: stage4 clean-box
	cd ansible && .venv/bin/ansible-playbook playbooks/build-vagrant-box.yml

vagrant:
	vagrant up --provider=libvirt

clean-vagrant:
	vagrant destroy -f

clean-box:
	vagrant destroy -f || true
	vagrant box remove k8s-node-ops-stage4 --all --force || true
	$(MAKE) clean-box-cache

clean-box-cache:
	virsh -c qemu:///system vol-list default | awk '/k8s-node-ops-stage4_vagrant_box_image_/ {print $$1}' | xargs -r -I{} virsh -c qemu:///system vol-delete {} --pool default

clean: clean-box
	rm -rf catalyst/work .vagrant vagrant/.vagrant vagrant/build ansible/vagrant /tmp/ansible_vagrant_box_*.tmp
	rm -f vagrant/*.box vagrant/vmlinuz vagrant/initramfs
