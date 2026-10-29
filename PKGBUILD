# Maintainer: Simon Hull <5488089+simonhull@users.noreply.github.com>

pkgname=omarchy-theme-schedule
pkgver=0.2.0
pkgrel=1
pkgdesc="Switch Omarchy themes on a daily schedule: light at sunrise, dark at sunset, or any times you pick"
arch=('any')
url="https://github.com/simonhull/omarchy-theme-schedule"
license=('MIT')
depends=('omarchy' 'bash' 'jq' 'gawk' 'perl' 'util-linux')
install=$pkgname.install
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('aa9464defc0ab47ea5dd0f26fee9bf894fde6002fe96804b49ac17bf9387a133')

check() {
  cd "$pkgname-$pkgver"
  make test
}

package() {
  cd "$pkgname-$pkgver"
  make DESTDIR="$pkgdir" PREFIX=/usr install
}
