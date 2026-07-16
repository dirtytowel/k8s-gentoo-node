.PHONY: stage4 box vagrant clean-vagrant clean-box-cache clean-box

stage4:
	cd catalyst && docker compose up

box: stage4 clean-box
	cd ansible && sudo ansible-playbook playbooks/build-vagrant-box.yml

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
