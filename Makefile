
FILE := multi.sol

FILE_CONTENT :=
FILE_CONTENT += import {
FILE_CONTENT +=     RhinestoneModuleKit,
FILE_CONTENT +=     RhinestoneModuleKitLib,
FILE_CONTENT +=     RhinestoneAccount
FILE_CONTENT += } from "modulekit/test/utils/$(TARGET)-base/RhinestoneModuleKit.sol";

account:
	@echo 'Setting up $(TARGET) tests'
	@echo '$(FILE_CONTENT)' > './.modulekit/$(FILE)'
	forge test --ffi

safe:
	$(MAKE) TARGET=safe account

biconomy:
	$(MAKE) TARGET=biconomy account

all:
	$(MAKE) safe
	$(MAKE) biconomy

install:
	@echo 'Installing dependencies'
	@yarn install
	@forge install

.PHONY: clean
clean:
	@rm -f $(TARGET)

