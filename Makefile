.PHONY: stage4 box vagrant clean-vagrant clean-box-cache

stage4:
	cd catalyst && docker compose up

box: clean-box-cache
	cd ansible && sudo ansible-playbook playbooks/build-vagrant-box.yml

vagrant:
	cd vagrant && vagrant up --provider=libvirt

clean-vagrant:
	cd vagrant && vagrant destroy -f

clean-box-cache:
	virsh -c qemu:///system vol-list default | awk '/k8s-node-ops-stage4_vagrant_box_image_/ {print $$1}' | xargs -r -I{} virsh -c qemu:///system vol-delete {} --pool default
