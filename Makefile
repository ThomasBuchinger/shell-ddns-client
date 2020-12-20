ddns-client.sh: providers/* utils.sh main.sh
	cat $^ > $@
	chmod 0755 $@

.PHONY: test
test: 
	bats test
