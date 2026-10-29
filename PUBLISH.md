# Yeni sürüm yayınlama (Claude bunu her güncellemede yapar)
1. `src/scripts/updater.gd` içinde `BUILD` bir artırılır, oyun Windows için dışa aktarılır.
2. `SOKAK.pck` 90 MB'lık parçalara bölünür ve `dist` dalına yüklenir.
3. Bu daldaki `version.json` yeni `build` numarası ve parçalarla güncellenir.
4. Oyuncular giriş ekranında **GÜNCELLE** butonunu görür; parçalar indirilir, birleştirilir, oyun yeniden açılır.
