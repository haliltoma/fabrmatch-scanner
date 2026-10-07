# Yeniden yapılandırma benchmark'ı

Sentetik taramalar (masa, mesafeye bağlı gürültü, uçan pikseller, sıyırma kaybı, poz hatası). Gerçek F-skoru eşiği: LiDAR 2.0 mm, TrueDepth 0.5 mm.

## Seçici

| sensör | parça | seçilen | F (CAD) | chamfer mm | en iyi (CAD) | F | pişmanlık |
|---|---|---|---|---|---|---|---|
| truedepth | flat_plate | 1pass:tsdf_0.5mm | 0.9879 | 0.069 | 1pass:tsdf_poisson_0.5mm | 0.9999 | 0.012 |
| truedepth | holed_bracket | 1pass:tsdf_poisson_0.5mm | 0.9874 | 0.12 | 1pass:tsdf_poisson_0.5mm | 0.9874 | 0.0 |
| truedepth | stepped_shaft | 1pass:tsdf_poisson_0.5mm | 0.9979 | 0.146 | 2pass:tsdf_poisson_0.5mm | 0.999 | 0.0011 |
| truedepth | thin_walled_box | 1pass:tsdf_poisson_0.5mm | 0.989 | 0.147 | 1pass:tsdf_poisson_0.5mm | 0.989 | 0.0 |
| truedepth | organic_handle | 2pass:poisson_d10 | 0.9445 | 0.202 | 2pass:poisson_d8 | 0.961 | 0.0165 |

**İyi seçim (pişmanlık ≤ 0.02): 5/5**

## Algoritmaların CAD'e F-skoru (kör: ayrılmış karelerde derinlik RMSE, mm)

| sensör | parça | 1pass:ball_pivoting | 1pass:poisson_d10 | 1pass:poisson_d8 | 1pass:poisson_d9 | 1pass:tsdf_0.5mm | 1pass:tsdf_1mm | 1pass:tsdf_2mm | 1pass:tsdf_poisson_0.5mm | 2pass:ball_pivoting | 2pass:poisson_d10 | 2pass:poisson_d8 | 2pass:poisson_d9 | 2pass:tsdf_0.5mm | 2pass:tsdf_1mm | 2pass:tsdf_2mm | 2pass:tsdf_poisson_0.5mm |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| truedepth | flat_plate | hata | 0.9426 (0.8305) | 0.9574 (0.8038) | 0.923 (0.8406) | 0.9879 (0.8028) | 0.9338 (0.8192) | 0.9065 (0.8953) | 0.9999 (0.8039) | None (None) | None (None) | None (None) | None (None) | None (None) | None (None) | None (None) | None (None) |
| truedepth | holed_bracket | hata | 0.9177 (0.9785) | 0.9099 (0.9904) | 0.9108 (1.0006) | 0.7311 (0.8567) | 0.7099 (0.8726) | 0.3881 (1.166) | 0.9874 (0.8014) | hata | 0.8881 (1.0676) | 0.8846 (1.0232) | 0.8729 (1.0261) | 0.9156 (0.8828) | 0.9015 (1.1191) | 0.3377 (1.4872) | 0.9115 (0.8514) |
| truedepth | stepped_shaft | hata | 0.9622 (0.876) | 0.9571 (0.879) | 0.9576 (0.8809) | 0.9944 (0.8535) | 0.9719 (0.8625) | 0.8194 (1.0267) | 0.9979 (0.8428) | hata | 0.9485 (0.895) | 0.9499 (0.9003) | 0.9422 (0.9008) | 0.9985 (0.9337) | 0.9775 (0.9661) | 0.7358 (1.1237) | 0.999 (0.9598) |
| truedepth | thin_walled_box | hata | 0.8633 (1.0468) | 0.8648 (1.0608) | 0.8628 (1.0479) | hata | 0.6078 (1.1895) | 0.2683 (1.7489) | 0.989 (0.9032) | hata | 0.7203 (1.3288) | 0.7449 (1.3456) | 0.7212 (1.3234) | 0.7926 (1.0796) | 0.4393 (1.324) | 0.245 (1.6066) | 0.7813 (1.1545) |
| truedepth | organic_handle | hata | 0.7065 (1.3824) | 0.703 (1.38) | 0.705 (1.3542) | 0.5746 (1.4571) | 0.566 (1.409) | 0.5336 (1.4801) | 0.6766 (1.4015) | hata | 0.9445 (1.0358) | 0.961 (1.0582) | 0.9331 (1.0705) | 0.9464 (1.1419) | 0.9549 (1.2085) | 0.7092 (1.3644) | 0.9449 (1.1216) |
