pi-gen-micro is a system designed to build **tiny** embedded operating systems from the same package sources as Raspberry Pi OS.

Why? Because this means you get the latest hardware support and updates in line with a widely-used and tested OS.

# Installing

## Build the package

Requires standard Debian developer packages:

    sudo apt install -y devscripts debhelper build-essential
    debuild -uc -us

## Installing the package

    sudo apt install -y ../pi-gen-micro_0.9.1_all.deb

# Usage

    pi-gen-micro-sysroot run <configuration> [target_devices]

On a host that isn't Raspberry Pi OS, `pi-gen-micro-sysroot` supplies the Debian
userland and Raspberry Pi tooling the build needs — see [Building on a host that
isn't Raspberry Pi OS](#building-on-a-host-that-isnt-raspberry-pi-os). It also
runs the build in a user namespace, which is worth having on its own:
`delete.list` and `generic_delete.list` are applied with an unquoted,
glob-expanded `rm -rf`, and under `sudo` that runs as real root against the host.

`pi-gen-micro` can equally be invoked directly:

    pi-gen-micro <configuration> [target_devices]

Run `pi-gen-micro --help` to see available configurations and options.

Output is written to `$PWD/out_image/`. It is recommended to run from a temporary directory:

    pushd $(mktemp -d)
    pi-gen-micro-sysroot run fastboot

## Target devices

An optional comma-separated list of target devices can be passed as the second argument to limit which device trees and firmware files are included. If omitted, files for all supported devices are included.

Supported targets: `pi3`, `cm3`, `cm0`, `pi4`, `400`, `cm4`, `pi5`, `500`, `cm5`, `02W`

Family shorthands expand to the devices sharing an SoC's firmware and device
trees: `pi5-family` (`cm5`, `pi5`, `500`), `pi4-family` (`cm4`, `400`, `pi4`)
and `pi3-family` (`pi3`, `cm3`, `02W`, `cm0`). Building one image per family keeps
out firmware the target cannot load, roughly halving a fastboot image.

    pi-gen-micro-sysroot run fastboot cm5,pi5

# Building on a host that isn't Raspberry Pi OS

The instructions above assume Raspberry Pi OS, or another Debian of the image's
own architecture. `pi-gen-micro-sysroot` lifts that requirement: it
bootstraps a throwaway Debian sysroot with `mmdebstrap`, installs the Raspberry
Pi archive tooling into it, and runs `pi-gen-micro` inside it in an
unprivileged user namespace. Nothing is installed on the host.

    pi-gen-micro-sysroot run fastboot cm5,pi5

Output lands in `$PWD/out_image/` and is owned by you, exactly as for a native
build.

A sysroot is only bootstrapped when the host needs one. Where the host is
already the image's architecture and has pi-gen-micro's tooling — a Raspberry
Pi, or any Debian of that architecture — the build runs **in place** and only
the namespace is set up, so nothing is downloaded. `USE_SYSROOT` overrides the choice: `auto` (default), `1` to always
bootstrap, `0` to never. `status` reports which mode applies.

The namespace earns its keep even in place: it stops `delete.list` and
`generic_delete.list` — which are applied with an unquoted, glob-expanded
`rm -rf` — from running as real root.

When a sysroot is used it is created on first use, reused afterwards, and is
about 150 MB:

    pi-gen-micro-sysroot create     # bootstrap (implied by run/shell)
    pi-gen-micro-sysroot status     # paths, suite, architecture, state
    pi-gen-micro-sysroot shell      # poke around inside a failed build
    pi-gen-micro-sysroot update     # apt update && dist-upgrade
    pi-gen-micro-sysroot clean      # remove build artefacts from $PWD
    pi-gen-micro-sysroot remove     # delete it

Use `clean` rather than `rm -rf` to tidy a build tree: `dpkg` chowns unpacked
files to non-root ids, which land as subuids on the host and cannot be unlinked
from outside the namespace. Rebuilding needs no cleanup either way, since
`pi-gen-micro` clears `build/` and `dpkg_admin/` itself.

Run from a git checkout, it points `pi-gen-micro` at the checkout, so edits to
configurations and helper packages take effect immediately with no reinstall.

## Host requirements

Always: `uidmap`, an entry in `/etc/subuid` and `/etc/subgid` for your user
(usually created with the account), and unprivileged user namespaces enabled.

Only when a sysroot is needed:

    sudo apt install -y mmdebstrap gnupg curl

Building for an architecture that is not the host's additionally needs
`qemu-user-static` and `binfmt-support`, since `binfmt_misc` registration is
kernel-wide and cannot be arranged from inside the tool.

## Why a sysroot, and why it matches the image's architecture

`pi-gen-micro` needs `rpi-make-boot-image` and `rpi-modcopy`, which only the
Raspberry Pi archive publishes, plus the Debian and Raspberry Pi keyrings. The
sysroot is where those come from — hence "fetching the Raspberry Pi packages it
needs to operate" rather than expecting them on the host.

The sysroot's architecture matches the image's (default `arm64`) rather than the
host's, and that is not a preference. `dpkg` has its native architecture
compiled in and cannot be told to treat another as native. An amd64 `dpkg`
therefore sees the image's arm64 packages as foreign, and an `Architecture: all`
package's unqualified dependencies — `libpam-runtime` needing `libpam-modules`,
say — can never be satisfied by them. Running an arm64 `dpkg` under `qemu-user`
costs wall-clock time and removes the whole class of problem. On an arm64 host
it is native and free.

### Native helpers

The emulation cost is concentrated in the arch-neutral stages, and it is not
subtle: compressing a 70 MB initramfs with `zstd --ultra -22 --long` takes 21 s
natively against roughly nine minutes emulated.

`zstd` and `cpio` only transform bytes, so the sysroot uses the host's own
builds of them. `create` copies each host binary into `/native` with its
libraries and writes a wrapper that invokes it through the host's dynamic
loader, so the sysroot's glibc and the host's need not agree; `/native/bin` goes
first on `PATH`. Everything that touches packages — `dpkg`, `apt`, maintainer
scripts, `ldconfig`, `depmod` — stays native to the image, which is the whole
point of the sysroot's architecture. `status` reports which helpers are in
place, and a tool missing from the host is simply left emulated.

Extending the set is one string, `NATIVE_TOOLS`, but only tools that transform
data belong in it.

End to end, this took a `fastboot cm5` build on an x86 host from 20m40s to
13m01s.

## Archive keys

Keyrings are needed before apt can verify anything, so they are fetched over the
network and then checked against fingerprints recorded in the script:

    04B54C3CDCA79751B16BC6B5225629DF75B188BD  Debian 13 (trixie) archive
    CF8A1AF502A2AA2D763BAE7E82B129927FA3303E  Raspberry Pi archive

A host keyring is reused when it already contains the expected key. Supporting
another suite means adding a line to the `case` on `SYSROOT_DIST`.

Two wrinkles are worth knowing about, because both present as "the repository is
not signed":

- The bootstrap apt runs *outside* the chroot with `Dir=<root>`, but `Signed-By`
  is read as a plain filesystem path and is not rewritten relative to `Dir`. The
  sources written during bootstrap therefore name the keyrings by host path, and
  are replaced with in-chroot ones before the sysroot is packed up.
- The Raspberry Pi archive key carries SHA1 self-certifications, which apt on
  trixie — Sequoia-based rather than `gpgv`-based — rejects from 2026-02-01
  onwards. The sysroot ships a relaxed hash policy at
  `/etc/crypto-policies/back-ends/apt-sequoia.config` to accept them.

## How it works

Bootstrap goes to a tarball rather than straight to a directory: `mmdebstrap`'s
`unshare` mode writes as a subuid, and extracting the tar ourselves is what
keeps the tree owned by — and therefore deletable by — you.

Builds then run as uid 0 in a user namespace that maps you to root and your
subuid/subgid range to 1..N. Mapping the range matters because `dpkg` chowns
unpacked files to non-root ids; mapping you (rather than a subuid) to root
matters so that the output is yours afterwards. `/dev`, `/proc` and `/sys` are
bind-mounted in, and both the source tree and `$PWD` are bound at identical
paths inside and out, so every path the build prints means the same thing in
both.

This mirrors the rootless chroot helpers in `rpi-imager`'s `debian/` directory,
which solve the same problem for Qt builds.

# Configurations

pi-gen-micro ships with several built-in configurations. Each configuration has a `description` file with a one-line summary. To list them:

    pi-gen-micro --list-configurations

## Creating a custom configuration

Create a new directory under the configurations path (default: `/var/lib/pi-gen-micro/configurations/`) with the following files:

### Required files

`build.parameters`  
Sourced as a shell script. Sets build-time variables:

- `KERNEL_BIT_SIZE` — kernel architecture (default: `64`)

- `HAS_CUSTOM_KERNEL` — set to `1` to use a custom kernel (also requires `CUSTOM_KERNEL_PATH` and `CUSTOM_KERNEL_VERSION_STR`)

`components.parameters`  
Sourced as a shell script. Feature flags that control what gets installed:

- `SYSTEMD=1` — use systemd as init system (default). Set to `0` for busybox init with `/etc/inittab` and shell scripts instead. Some helper packages (e.g. `cryptroot`) require systemd.

- `SSH=1` — install dropbear SSH server (requires an `authorized_keys` file in internal/prebuilts)

- `UDEV=1` — install udev for dynamic device management

- `NETWORK=1` — install networking. With systemd: systemd-networkd and systemd-resolved (requires `UDEV=1`). Without systemd: busybox `udhcpc`.

- `AUTOLOGIN=1` — enable automatic root login on console and serial

`packages.list`  
Newline-separated list of additional packages to install into the image. These are installed via `apt` from the configured sources.

`kernel_modules.list`  
Newline-separated list of kernel modules to include. Modules and their dependencies are resolved and copied using `rpi-modcopy`.

`installer_scripts.list`  
An executable script (not a list, despite the name) run after packages are installed. The configuration directory is added to `PATH`, so scripts within the configuration directory can be called by name.

`dpkg_extra_args`  
dpkg `path-exclude` / `path-include` rules to reduce image size by excluding documentation, locales, etc. Lines starting with `#` are ignored.

### Optional files

`description`  
A one-line description of the configuration, shown by `pi-gen-micro --list-configurations` and in error messages.

`cmdline.txt`  
Custom kernel command line, overriding the default from prebuilts.

`config.txt`  
Custom firmware configuration, overriding the default from prebuilts.

`post_creation.sh`  
Executable script run after the full image is assembled. Useful for cleanup or additional modifications.

`udebs.list`  
Newline-separated list of udeb packages to install as substitute packages (patched with `Provides`/`Replaces`/`Conflicts` to satisfy dependencies).

`delete.list`  
Newline-separated list of paths to delete from the final image.

`generic_delete.list`  
Newline-separated list of filename patterns to delete from the final image (matched by `find -name`).

# Helper packages

pi-gen-micro includes a local package repository at `/var/lib/pi-gen-micro/internal/packages/`. Configurations install packages from this repository (alongside standard Debian and Raspberry Pi OS repositories) by listing them in their `packages.list`.

The source for each helper package lives under `helper-packages/` (installed to `/var/lib/pi-gen-micro/helper-packages/`). Each is a directory containing a `control` file (binary package metadata), an `install` file (file-to-destination mappings with permissions), and optionally a `links` file (symlinks).

## Automatic building

When `pi-gen-micro` runs, it automatically builds all helper packages from source using `dpkg-deb` and regenerates the package index before the build starts. This means edits to helper package sources take effect on the next `pi-gen-micro` run with no manual steps.

## Included helper packages

Each helper package has a full description in its `control` file. To list all available packages with their descriptions:

    pi-gen-micro --list-packages

The descriptions are also embedded in the built `.deb` metadata, viewable with `dpkg --info <package>.deb`.

## Using `build-packages` directly

The `build-packages` script can also be used standalone:

    build-packages --dry-run              # show what would be built
    build-packages                        # rebuild all helper packages
    build-packages cryptroot ssh-service  # rebuild specific packages only

## Adding a new helper package

1.  Create a directory under `helper-packages/` (e.g. `helper-packages/my-package/`).

2.  Add the files to be packaged, a `control` file (standard Debian binary package control format), an `install` file (lines of `<source> <dest-dir> <mode>`), and optionally a `links` file (lines of `<target> <link-path>`).

3.  Add the directory to `debian/install` so it is installed under `/var/lib/pi-gen-micro/helper-packages/`:

        helper-packages/my-package          /var/lib/pi-gen-micro/helper-packages

4.  Reference the package name (from `control`, not the directory name) in your configuration’s `packages.list`.

The package will be built automatically on the next `pi-gen-micro` run.

## Adding external pre-built packages

To include a `.deb` not built from a helper package source (e.g. `rpi-fastbootd`, `rpi-imager-embedded`):

1.  Place the `.deb` file in the `internal/packages/` directory.

2.  Reference the package name in your configuration’s `packages.list`.

The package index is regenerated automatically when `build-packages` runs (which happens at the start of every `pi-gen-micro` build), so no manual steps are needed. `build-packages` does not touch `.deb` files that lack a corresponding helper package source, so externally-provided packages are preserved across rebuilds.
