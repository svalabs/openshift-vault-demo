.PHONY: docs
docs:
	gh-md-toc --insert README.md
	make -C . clean

.PHONY: clean
clean:
	rm README.md.*