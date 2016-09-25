#!/usr/bin/env make
# Release engineering for bash-prompt-vcs.bash
#
# Copyright (c) 2016 Marc Meadows
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
#
RELEASE_ARCHIVE  = release.tgz
RELEASE_CONTENTS = bash-prompt-vcs.bash LICENSE README.md
TESTS            = test-bash-prompt-vcs debug-util.bash

release: $(RELEASE_ARCHIVE)

# Yeah, the phony test target can never be satisfied, so the tests will run
# every time you make the release archive.  This is intentional.
$(RELEASE_ARCHIVE): $(RELEASE_CONTENTS) $(TESTS) test
	tar czvf $@ $(RELEASE_CONTENTS)

version:
	@grep 'BPVCS_VERSION=' bash-prompt-vcs.bash | sed 's/.*="\(.*\)"/\1/'

test:
	./test-bash-prompt-vcs

# In case of test failures, the sandboxes are left around in /tmp for 
# forensics.  This command will clean them up.  If all tests pass, this is
# not necessary as the tests will clean them up.
testcleanup:
	rm -rf /tmp/bpvcs-test*

clean:
	rm -f $(RELEASE_ARCHIVE)
