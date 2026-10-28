# Maintainer: Simon Hull <5488089+simonhull@users.noreply.github.com>

pkgname=omarchy-theme-schedule
pkgver=0.1.0
pkgrel=1
pkgdesc="Switch Omarchy themes on a daily schedule: light at sunrise, dark at sunset, or any times you pick"
arch=('any')
url="https://github.com/simonhull/omarchy-theme-schedule"
license=('MIT')
depends=('omarchy' 'bash' 'jq' 'gawk' 'perl' 'util-linux')
install=$pkgname.install
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
# Replace with the real checksum (updpkgsums) when the v$pkgver tag is published.
sha256sums=('SKIP')

check() {
  cd "$pkgname-$pkgver"
  make test
}

package() {
  cd "$pkgname-$pkgver"
  make DESTDIR="$pkgdir" PREFIX=/usr install
}
