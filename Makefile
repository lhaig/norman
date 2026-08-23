REPO        := $(CURDIR)
CLAUDE_HOME := $(HOME)/.claude
SKILLS      := $(CLAUDE_HOME)/skills
BACKUP      := $(CLAUDE_HOME)/.repo-sync-backup-$(shell date +%Y%m%d-%H%M%S)

LINKS := \
	$(SKILLS)/norman:$(REPO)/norman \
	$(SKILLS)/prd:$(REPO)/prd \
	$(SKILLS)/sweep:$(REPO)/sweep \
	$(CLAUDE_HOME)/agents:$(REPO)/agents \
	$(CLAUDE_HOME)/statusline.sh:$(REPO)/statusline/statusline.sh

.PHONY: install uninstall status help

help:
	@echo "Targets:"
	@echo "  install    Symlink skills/agents/statusline from this repo into ~/.claude/"
	@echo "             (backs up existing real files/dirs to a timestamped folder)"
	@echo "  uninstall  Remove symlinks that point into this repo (leaves backups)"
	@echo "  status     Show current link state of each managed path"

install:
	@mkdir -p "$(SKILLS)"
	@for pair in $(LINKS); do \
		dest=$${pair%%:*}; src=$${pair##*:}; \
		if [ -L "$$dest" ]; then \
			if [ "$$(readlink "$$dest")" = "$$src" ]; then \
				echo "[skip] $$dest -> already linked"; \
				continue; \
			fi; \
			echo "[relink] $$dest -> $$src"; \
			rm "$$dest"; \
		elif [ -e "$$dest" ]; then \
			mkdir -p "$(BACKUP)"; \
			echo "[backup] $$dest -> $(BACKUP)/"; \
			mv "$$dest" "$(BACKUP)/" || exit 1; \
			echo "[link]   $$dest -> $$src"; \
		else \
			echo "[link]   $$dest -> $$src"; \
		fi; \
		ln -s "$$src" "$$dest" || exit 1; \
	done
	@echo "Done. Run 'make status' to verify."

uninstall:
	@for pair in $(LINKS); do \
		dest=$${pair%%:*}; src=$${pair##*:}; \
		if [ -L "$$dest" ] && [ "$$(readlink "$$dest")" = "$$src" ]; then \
			rm "$$dest"; echo "[unlink] $$dest"; \
		else \
			echo "[skip]   $$dest (not a symlink into this repo)"; \
		fi; \
	done

status:
	@for pair in $(LINKS); do \
		dest=$${pair%%:*}; src=$${pair##*:}; \
		if [ -L "$$dest" ]; then \
			target=$$(readlink "$$dest"); \
			if [ "$$target" = "$$src" ]; then \
				echo "[ok]   $$dest -> $$target"; \
			else \
				echo "[warn] $$dest -> $$target (expected $$src)"; \
			fi; \
		elif [ -e "$$dest" ]; then \
			echo "[real] $$dest (not a symlink)"; \
		else \
			echo "[miss] $$dest"; \
		fi; \
	done
