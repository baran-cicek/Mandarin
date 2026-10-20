.PHONY: build test app install uninstall deps clean check-tty

build:
	swift build -c release

test:
	swift run MandarinSelfTests

app:
	./build.sh

deps:
	brew bundle --file=Brewfile

install:
	./install.sh

uninstall:
	./uninstall.sh

clean:
	rm -rf .build dist

check-tty:
	./check-tty.sh
