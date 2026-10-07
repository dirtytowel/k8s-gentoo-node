INVENTORY ?= inventory/vagrant.yml

.PHONY: venv kubeconfig stage4 box vagrant vagrant-clean clean

venv:
	python3 -m venv .venv
	.venv/bin/pip install --no-cache-dir -r requirements.txt
	.venv/bin/ansible-galaxy collection install -r requirements.yml -p .venv/collections --force

kubeconfig:
	.venv/bin/ansible-playbook -i $(INVENTORY) playbooks/save-kubeconfig.yml

stage4:
	.venv/bin/ansible-playbook -i $(INVENTORY) playbooks/catalyst.yml
	cd catalyst && docker compose run --rm --build catalyst

box: vagrant-clean
	.venv/bin/ansible-playbook playbooks/build-vagrant-box.yml

vagrant:
	vagrant up --provider=libvirt

vagrant-clean:
	vagrant destroy -f || true
	vagrant box remove k8s-node-ops-stage4 --all --force || true
	virsh -c qemu:///system vol-list default | awk '/k8s-node-ops-stage4_vagrant_box_image_/ {print $$1}' | xargs -r -I{} virsh -c qemu:///system vol-delete {} --pool default

clean: vagrant-clean
	rm -rf catalyst/work .vagrant vagrant/.vagrant vagrant/build ansible/vagrant /tmp/ansible_vagrant_box_*.tmp
	rm -f vagrant/*.box vagrant/vmlinuz vagrant/initramfs
