# Yeniden yapılandırma benchmark'ı

Sentetik taramalar (masa, mesafeye bağlı gürültü, uçan pikseller, sıyırma kaybı, poz hatası). Gerçek F-skoru eşiği: LiDAR 2.0 mm, TrueDepth 0.5 mm.

## Seçici

| sensör | parça | seçilen | F (CAD) | chamfer mm | en iyi (CAD) | F | pişmanlık |
|---|---|---|---|---|---|---|---|
| truedepth | flat_plate | tsdf_poisson_0.5mm | 0.9998 | 0.066 | tsdf_poisson_0.5mm | 0.9998 | 0.0 |
| truedepth | holed_bracket | tsdf_poisson_0.5mm | 0.9878 | 0.12 | tsdf_poisson_0.5mm | 0.9878 | 0.0 |
| truedepth | stepped_shaft | tsdf_poisson_0.5mm | 0.9982 | 0.145 | tsdf_poisson_0.5mm | 0.9982 | 0.0 |
| truedepth | thin_walled_box | tsdf_poisson_0.5mm | 0.9894 | 0.149 | tsdf_poisson_0.5mm | 0.9894 | 0.0 |
| truedepth | organic_handle | poisson_d10 | 0.7211 | 0.879 | poisson_d10 | 0.7211 | 0.0 |
| lidar | flat_plate | — | — | — | — | — | no object found above the table: with this sensor's noise the table ba |
| lidar | holed_bracket | tsdf_3mm | 0.6555 | 3.533 | tsdf_2mm | 0.7187 | 0.0632 |
| lidar | stepped_shaft | tsdf_3mm | 0.9581 | 0.689 | tsdf_3mm | 0.9581 | 0.0 |
| lidar | thin_walled_box | poisson_d7 | 0.6164 | 1.953 | tsdf_3mm | 0.6787 | 0.0623 |
| lidar | organic_handle | tsdf_3mm | 0.6845 | 1.914 | tsdf_poisson_2mm | 0.8624 | 0.1779 |

**İyi seçim (pişmanlık ≤ 0.02): 6/9** · yeniden yapılandırılamayan: 1 (lidar/flat_plate)

## Algoritmaların CAD'e F-skoru (kör: ayrılmış karelerde derinlik RMSE, mm)

| sensör | parça | ball_pivoting | poisson_d10 | poisson_d7 | poisson_d8 | poisson_d9 | tsdf_0.5mm | tsdf_1mm | tsdf_2mm | tsdf_3mm | tsdf_5mm | tsdf_poisson_0.5mm | tsdf_poisson_2mm |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| truedepth | flat_plate | hata | 0.9401 (0.8283) | None (None) | 0.9573 (0.801) | 0.9259 (0.8379) | 0.6835 (0.8411) | 0.9329 (0.8121) | 0.9057 (0.8853) | None (None) | None (None) | 0.9998 (0.7992) | None (None) |
| truedepth | holed_bracket | hata | 0.9185 (0.9815) | None (None) | 0.9091 (0.9945) | 0.9092 (1.0046) | 0.7272 (0.8285) | 0.8607 (0.8316) | 0.3835 (1.1557) | None (None) | None (None) | 0.9878 (0.8005) | None (None) |
| truedepth | stepped_shaft | hata | 0.9599 (0.8759) | None (None) | 0.9552 (0.8806) | 0.9592 (0.881) | 0.9819 (0.8533) | 0.9709 (0.8631) | 0.8145 (1.0293) | None (None) | None (None) | 0.9982 (0.8431) | None (None) |
| truedepth | thin_walled_box | hata | 0.8647 (1.0726) | None (None) | 0.8666 (1.0775) | 0.864 (1.0738) | 0.6983 (1.5593) | 0.3384 (1.7052) | 0.1596 (2.0215) | None (None) | None (None) | 0.9894 (0.9164) | None (None) |
| truedepth | organic_handle | hata | 0.7211 (1.3513) | None (None) | 0.711 (1.4071) | 0.7114 (1.403) | 0.6055 (1.4338) | 0.5652 (1.408) | 0.526 (1.4789) | None (None) | None (None) | 0.6812 (1.4176) | None (None) |
| lidar | flat_plate | None (None) | None (None) | None (None) | None (None) | None (None) | None (None) | None (None) | None (None) | None (None) | None (None) | None (None) | None (None) |
| lidar | holed_bracket | hata | None (None) | 0.5682 (9.5651) | 0.5656 (9.5025) | 0.5639 (9.5025) | None (None) | None (None) | 0.7187 (7.2312) | 0.6555 (6.4295) | 0.4113 (7.7932) | None (None) | hata |
| lidar | stepped_shaft | hata | None (None) | 0.7091 (8.2896) | 0.7159 (8.2578) | 0.726 (8.2577) | None (None) | None (None) | 0.904 (7.5474) | 0.9581 (7.2399) | 0.7992 (8.511) | None (None) | 0.9141 (7.4265) |
| lidar | thin_walled_box | 0.4324 (17.9582) | None (None) | 0.6164 (12.4073) | 0.622 (12.4328) | 0.626 (12.4329) | None (None) | None (None) | 0.5324 (17.9046) | 0.6787 (14.0009) | 0.6647 (13.0852) | None (None) | 0.5468 (17.907) |
| lidar | organic_handle | hata | None (None) | 0.5252 (12.5167) | 0.5516 (12.171) | 0.5456 (12.1708) | None (None) | None (None) | hata | 0.6845 (9.7893) | 0.6233 (10.3222) | None (None) | 0.8624 (10.2179) |
