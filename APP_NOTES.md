# Catatan Stomatrade

- **Tujuan**: kontrak `Stomatrade` memfasilitasi pendanaan proyek pertanian memakai token ERC20 (IDRX), serta NFT berisi metadata IPFS untuk farmer, proyek, dan bukti investasi.
- **Peran**: hanya `owner` yang bisa menambah farmer, membuat/menutup/mengubah status proyek, dan menyelesaikan proyek (deposit profit + modal). Investor publik hanya dapat berinvestasi dan klaim refund/withdraw sesuai status.

## Model Data
- **IDRX**: token ERC20 eksternal (mock di `src/MockIDRX.sol`) sebagai satu-satunya aset yang dipindahkan.
- **NFT**: kontrak adalah ERC721; mint opsional jika CID tidak kosong. ID token = `idFarmer`, `idProject`, atau `idInvestment` (masing-masing counter mulai dari 1) sehingga ada potensi tabrakan ID jika mint untuk jenis berbeda dengan nilai sama.
- **Farmer** (`Farmers`): `idCollector`, `name`, `age`, `domicile`; hanya dicatat oleh owner melalui `addFarmer`.
- **Project** (`projects`): `valueProject`, `maxInvested`, `totalRaised`, `totalKilos`, `profitPerKillos`, `sharedProfit (persentase untuk investor)`, `status`.
- **Investment** (`contribution`): per proyek per investor: `id` global, `amount`, dan `status (UNCLAIMED/CLAIMED)`; mirror ke `investmentsByTokenId`.

## Siklus Proyek
1) **Buat proyek** (`createProject`): owner set parameter + status `ACTIVE`; mint NFT proyek opsional ke owner.
2) **Investasi** (`invest`): hanya saat `ACTIVE`; transfer IDRX ke kontrak, cap terhadap `maxInvested` (kelebihan dipangkas); buat/tingkatkan Investment; bisa mint NFT investasi. Jika `totalRaised == maxInvested`, status otomatis `CLOSED`.
3) **Refund** (`refundProject` → `claimRefund`): owner set status `REFUND`; investor UNCLAIMED tarik kembali `amount` (status jadi `CLAIMED`, `amount` di-nolkan, `totalRaised` dikurangi).
4) **Sukses** (`finishProject` → `claimWithdraw`): sebelum status `SUCCESS`, owner harus deposit `totalRaised + investorProfitPool` (dihitung dari `totalKilos * profitPerKillos * sharedProfit/100`). Investor menarik `principal + bagi hasil proporsional`; dana keluar dari kontrak.
5) **Close manual** (`closeProject`): ubah status ke `CLOSED` tanpa refund/withdraw logika tambahan.

## Fungsi Bantu
- `getProjectProfitBreakdown`: kembalikan `grossProfit`, bagian investor, dan profit platform.
- `getInvestorReturn`: hitung principal, profit, total bagi investor berdasarkan porsi `amount/totalRaised`.
- `getAdminRequiredDeposit`: total deposit yang wajib disetor owner sebelum `finishProject` (principal + total profit investor).

## Skrip & Tes
- Deploy contoh di `script/Deploy.s.sol` (deploy `MockIDRX` dan `Stomatrade`, menampilkan perintah verifikasi).
- Pengujian Foundry di `test/StomaTrade.t.sol` mencakup happy path & banyak revert case (investasi, refund, withdraw, profit breakdown, variasi sharedProfit, minting NFT, dsb).

## Catatan Risiko/Keterbatasan
- ID NFT lintas entitas dapat berbenturan (contoh proyek ID 1 dan investasi pertama sama-sama tokenId 1 jika keduanya di-mint); beberapa tes menghindari mint proyek untuk mencegah konflik.
- NFT tidak di-lock (tidak SBT); kepemilikan dapat dialihkan meskipun fungsinya sebagai bukti partisipasi.
- Tidak ada guardrail fee/precision: konstanta `DECIMAL_*` dan `FEE_PER_TX` belum dipakai; profit kalkulasi pakai bilangan bulat 18 desimal penuh.
