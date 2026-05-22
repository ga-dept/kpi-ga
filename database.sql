-- =====================================================================
--  GASS Terus! — KPI Management System
--  General Affairs Department · PT MRT Jakarta (Perseroda)
--  Skema basis data MySQL / MariaDB
--
--  Versi  : 2.0 (2026)
--  Mesin  : InnoDB, charset utf8mb4
--
--  Catatan:
--  Skema ini merupakan padanan server-side dari struktur data yang
--  dipakai aplikasi single-file (index.html / localStorage key gass_db_v2).
--  Untuk implementasi produksi, kolom password sebaiknya disimpan dalam
--  bentuk hash (mis. bcrypt). Pada seed di bawah, password ditulis
--  sebagaimana di prototipe untuk memudahkan pengujian.
-- =====================================================================

DROP DATABASE IF EXISTS `gass_terus_db`;
CREATE DATABASE `gass_terus_db`
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;
USE `gass_terus_db`;

-- ---------------------------------------------------------------------
--  Urutan DROP memperhatikan dependensi foreign key (anak lebih dulu)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS `kpi_submission_details`;
DROP TABLE IF EXISTS `kpi_submissions`;
DROP TABLE IF EXISTS `employee_kpi_weights`;
DROP TABLE IF EXISTS `kpi_key_results`;
DROP TABLE IF EXISTS `kpi_objectives`;
DROP TABLE IF EXISTS `kpi_periods`;
DROP TABLE IF EXISTS `notifications`;
DROP TABLE IF EXISTS `activity_logs`;
DROP TABLE IF EXISTS `popup_notifications`;
DROP TABLE IF EXISTS `users`;


-- =====================================================================
--  TABEL: users
--  Akun pengguna sistem. Role: superadmin | admin | employee.
--  Superadmin utama: arizki (tidak boleh dihapus dari aplikasi).
-- =====================================================================
CREATE TABLE `users` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `nik`        VARCHAR(30)  NOT NULL,
  `name`       VARCHAR(150) NOT NULL,
  `username`   VARCHAR(60)  NOT NULL,
  `password`   VARCHAR(255) NOT NULL,
  `jabatan`    VARCHAR(200) NOT NULL,
  `role`       ENUM('superadmin','admin','employee') NOT NULL DEFAULT 'employee',
  `status`     ENUM('active','inactive') NOT NULL DEFAULT 'active',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_users_username` (`username`),
  UNIQUE KEY `uq_users_nik` (`nik`),
  KEY `idx_users_role` (`role`),
  KEY `idx_users_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  TABEL: kpi_periods
--  Periode penilaian KPI tahunan. Hanya satu periode boleh 'active'.
-- =====================================================================
CREATE TABLE `kpi_periods` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `year`       SMALLINT UNSIGNED NOT NULL,
  `name`       VARCHAR(120) NOT NULL,
  `status`     ENUM('active','closed','draft') NOT NULL DEFAULT 'draft',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_periods_status` (`status`),
  KEY `idx_periods_year` (`year`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  TABEL: kpi_objectives
--  Objective KPI per periode.
--  target_type : annual | monthly | score
--  score_type  : weighted (skor dihitung dari bobot KR)
--                direct   (nilai input langsung dipakai sebagai skor)
-- =====================================================================
CREATE TABLE `kpi_objectives` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `period_id`   INT UNSIGNED NOT NULL,
  `name`        VARCHAR(255) NOT NULL,
  `formula`     TEXT NULL,
  `target_type` ENUM('annual','monthly','score') NOT NULL DEFAULT 'annual',
  `score_type`  ENUM('weighted','direct') NOT NULL DEFAULT 'weighted',
  `created_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_obj_period` (`period_id`),
  CONSTRAINT `fk_obj_period`
    FOREIGN KEY (`period_id`) REFERENCES `kpi_periods` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  TABEL: kpi_key_results
--  Key Result (KR) untuk setiap objective.
--  relative_weight = bobot KR dalam objective; total per objective = 100.
-- =====================================================================
CREATE TABLE `kpi_key_results` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `objective_id`    INT UNSIGNED NOT NULL,
  `description`     VARCHAR(400) NOT NULL,
  `target`          DECIMAL(12,2) NOT NULL DEFAULT 0,
  `unit`            VARCHAR(40)  NULL,
  `relative_weight` DECIMAL(6,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_kr_objective` (`objective_id`),
  CONSTRAINT `fk_kr_objective`
    FOREIGN KEY (`objective_id`) REFERENCES `kpi_objectives` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  TABEL: employee_kpi_weights
--  Bobot tiap objective KPI yang dibebankan ke seorang karyawan.
--  Total weight per (user, periode) idealnya = 100.
-- =====================================================================
CREATE TABLE `employee_kpi_weights` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`      INT UNSIGNED NOT NULL,
  `objective_id` INT UNSIGNED NOT NULL,
  `weight`       DECIMAL(6,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_weight_user_obj` (`user_id`,`objective_id`),
  KEY `idx_weight_user` (`user_id`),
  KEY `idx_weight_obj` (`objective_id`),
  CONSTRAINT `fk_weight_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_weight_obj`
    FOREIGN KEY (`objective_id`) REFERENCES `kpi_objectives` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  TABEL: kpi_submissions
--  Hasil penilaian KPI satu karyawan untuk satu objective di satu periode.
--  edit_count : jumlah kali sudah diedit (maks. 3 - lalu terkunci).
--  total_score: akumulasi skor berbobot dari seluruh KR.
--  final_sf   : Skor Final (80/90/100/110/120) hasil computeSf().
-- =====================================================================
CREATE TABLE `kpi_submissions` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`        INT UNSIGNED NOT NULL,
  `objective_id`   INT UNSIGNED NOT NULL,
  `period_id`      INT UNSIGNED NOT NULL,
  `total_score`    DECIMAL(10,2) NOT NULL DEFAULT 0,
  `final_sf`       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `status`         ENUM('draft','submitted','locked') NOT NULL DEFAULT 'submitted',
  `edit_count`     TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `declaration`    TINYINT(1) NOT NULL DEFAULT 0,
  `evidence_file`  VARCHAR(255) NULL,
  `evidence_note`  TEXT NULL,
  `signature_file` VARCHAR(255) NULL,
  `submitted_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_edited_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_submission` (`user_id`,`objective_id`,`period_id`),
  KEY `idx_sub_user` (`user_id`),
  KEY `idx_sub_obj` (`objective_id`),
  KEY `idx_sub_period` (`period_id`),
  CONSTRAINT `fk_sub_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_sub_obj`
    FOREIGN KEY (`objective_id`) REFERENCES `kpi_objectives` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_sub_period`
    FOREIGN KEY (`period_id`) REFERENCES `kpi_periods` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  TABEL: kpi_submission_details
--  Rincian realisasi tiap KR di dalam sebuah submission.
--  score_part = (realisasi / target) * relative_weight KR tersebut.
-- =====================================================================
CREATE TABLE `kpi_submission_details` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `submission_id` INT UNSIGNED NOT NULL,
  `key_result_id` INT UNSIGNED NOT NULL,
  `realisasi`     DECIMAL(12,2) NOT NULL DEFAULT 0,
  `score_part`    DECIMAL(10,4) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_det_submission` (`submission_id`),
  KEY `idx_det_kr` (`key_result_id`),
  CONSTRAINT `fk_det_submission`
    FOREIGN KEY (`submission_id`) REFERENCES `kpi_submissions` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_det_kr`
    FOREIGN KEY (`key_result_id`) REFERENCES `kpi_key_results` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  TABEL: activity_logs
--  Catatan aktivitas pengguna (login, CRUD KPI, submit, dll).
-- =====================================================================
CREATE TABLE `activity_logs` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`     INT UNSIGNED NULL,
  `action`      VARCHAR(60)  NOT NULL,
  `description` VARCHAR(400) NOT NULL,
  `created_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_log_user` (`user_id`),
  KEY `idx_log_created` (`created_at`),
  CONSTRAINT `fk_log_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  TABEL: notifications
--  Notifikasi lonceng per-orangan (mis. reminder KPI belum diisi).
--  type: info | warn | success
-- =====================================================================
CREATE TABLE `notifications` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL,
  `type`       ENUM('info','warn','success') NOT NULL DEFAULT 'info',
  `message`    VARCHAR(400) NOT NULL,
  `is_read`    TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_notif_user` (`user_id`),
  KEY `idx_notif_read` (`is_read`),
  CONSTRAINT `fk_notif_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  TABEL: popup_notifications
--  Konfigurasi pop-up pengumuman yang tampil di landing / CPanel.
--  target: both | landing | cpanel       type: info | warning | success
-- =====================================================================
CREATE TABLE `popup_notifications` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `title`      VARCHAR(200) NOT NULL,
  `content`    TEXT NOT NULL,
  `target`     ENUM('both','landing','cpanel') NOT NULL DEFAULT 'both',
  `type`       ENUM('info','warning','success') NOT NULL DEFAULT 'info',
  `active`     TINYINT(1) NOT NULL DEFAULT 1,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  SEED DATA
-- =====================================================================

-- --- users -----------------------------------------------------------
-- Superadmin utama: arizki / arizki01
-- Password karyawan lain = NIK masing-masing.
INSERT INTO `users`
  (`id`,`nik`,`name`,`username`,`password`,`jabatan`,`role`,`status`) VALUES
  (1, '10395',     'Rizki Aziz Radyantama',     'arizki',     'arizki01',  'Office Quality Facility Specialist',                                  'superadmin', 'active'),
  (2, '217051224', 'M. Ardhan Rafsanjani',      'ardhan',     '217051224', 'General Affairs Department Head',                                     'admin',      'active'),
  (3, '218022377', 'Maya Satih Kanteyan',       'maya',       '218022377', 'Site Office and Head Office Facility Operation Section Head',          'admin',      'active'),
  (4, '10077',     'Waziruddin',                'waziruddin', '10077',     'Depot Office Facility Operation Section Head',                        'admin',      'active'),
  (5, '10003',     'Annisa Mayangsari',         'annisa',     '10003',     'Site Office and Head Office Facility Operation Specialist',           'employee',   'active'),
  (6, '213031040', 'Rakhmat',                   'rakhmat',    '213031040', 'Site Office and Head Office Facility Operation Specialist',           'employee',   'active'),
  (7, '218111585', 'Agung Prasetyo Wicaksono',  'agung',      '218111585', 'Site Office and Head Office Facility Operation Specialist',           'employee',   'active'),
  (8, '10025',     'Siti Zahratus Solihat',     'siti',       '10025',     'Site Office and Head Office Facility Operation Specialist',           'employee',   'active'),
  (9, '217111362', 'Abdul Ajid',                'abdul',      '217111362', 'Depot Office Facility Operation Specialist',                          'employee',   'active'),
  (10,'10523',     'Dharisa Inayah Ramadhan',   'dharisa',    '10523',     'Depot Office Facility Operation Specialist',                          'employee',   'active');


-- --- kpi_periods -----------------------------------------------------
INSERT INTO `kpi_periods` (`id`,`year`,`name`,`status`) VALUES
  (1, 2025, 'Periode KPI 2025', 'closed'),
  (2, 2026, 'Periode KPI 2026', 'active');


-- --- kpi_objectives (periode 2026) -----------------------------------
INSERT INTO `kpi_objectives`
  (`id`,`period_id`,`name`,`formula`,`target_type`,`score_type`) VALUES
  (101,2,'Terlaksananya kegiatan budget controlling','Realisasi jumlah kegiatan terserap berdasarkan RKA; Efisiensi anggaran; Laporan tepat waktu.','annual','weighted'),
  (102,2,'Tercapainya success rate pengelolaan layanan umum','Efektivitas Departemen GA dalam menanggapi permintaan layanan (SLA).','annual','weighted'),
  (103,2,'Indeks Kepuasan Stakeholder','Pencapaian Indeks Kepuasan Stakeholder.','annual','weighted'),
  (104,2,'Jumlah Inisiatif Peningkatan Proses atau Efisiensi','Kontribusi staf dalam mengidentifikasi ide perbaikan proses kerja.','annual','weighted'),
  (105,2,'Petty Cash Handling','Akurasi saldo dan pencatatan kas kecil.','monthly','weighted'),
  (106,2,'Tingkat Kepatuhan Prosedur Keselamatan','Implementasi kebijakan K3 di lingkungan kantor.','annual','weighted'),
  (107,2,'Pengelolaan Inventaris Aset Kantor','Keakuratan data aset kantor vs fisik di lapangan.','annual','weighted'),
  (108,2,'Tingkat Kesesuaian Rencana Pengadaan','Jumlah pengadaan dengan waktu sesuai RPBJ.','annual','weighted'),
  (109,2,'Penyediaan Kantor Pusat PT MRT Jakarta','Tersedianya kajian perpindahan kantor pusat.','annual','weighted'),
  (110,2,'Optimasi Perjalanan Dinas Karyawan','Development integrasi perjalanan dinas pada platform milik PT MRTJ.','annual','weighted'),
  (111,2,'Tingkat pemenuhan IDP','Realisasi pemenuhan IDP.','score','direct'),
  (112,2,'Indeks Knowledge Management','Tercapainya Skor KM Index.','score','direct'),
  (113,2,'Indeks GRC','Terselesaikannya 100% pemenuhan GRC Direktorat.','annual','direct'),
  (114,2,'Penyelesaian Temuan Audit','Terselesaikannya 100% temuan audit.','annual','direct');


-- --- kpi_key_results -------------------------------------------------
INSERT INTO `kpi_key_results`
  (`id`,`objective_id`,`description`,`target`,`unit`,`relative_weight`) VALUES
  -- Objective 101 — budget controlling
  (1001,101,'Tingkat realisasi penyerapan anggaran',80,'%',40),
  (1002,101,'Cost Efficiency non subsidi ((RKA-Biaya)/RKA)*100%',5,'%',20),
  (1003,101,'Kedisiplinan pelaporan (max tgl 15 tiap bulan)',12,'Bulan',40),
  -- Objective 102 — success rate
  (1011,102,'Response time & SLA permintaan terpenuhi',100,'%',20),
  (1012,102,'Indeks Kepuasan Pelanggan Overall',80,'Skor',30),
  (1013,102,'Indeks Kepuasan Pelanggan per Specialist',80,'Skor',30),
  (1014,102,'Zero skip request per tahun',0,'Kali',20),
  -- Objective 103 — indeks kepuasan stakeholder
  (1021,103,'Pencapaian Indeks Kepuasan Stakeholder',100,'%',100),
  -- Objective 104 — inisiatif peningkatan proses
  (1031,104,'Presentasi project charter ke Kadep',1,'Dokumen',20),
  (1032,104,'Implementasi proyek 100%',100,'%',30),
  (1033,104,'Dokumentasi & laporan akhir',100,'%',20),
  (1034,104,'Membuat/Review SOP/IK/SE terkait',1,'Dokumen',30),
  -- Objective 105 — petty cash handling
  (1041,105,'Kepatuhan dokumentasi (Invoice/Bon)',100,'%',20),
  (1042,105,'Laporan rekonsiliasi petty cash tiap bulan',12,'Bulan',30),
  (1043,105,'Akurasi rekonsiliasi balance',100,'%',30),
  (1044,105,'Tidak ada keterlambatan pengisian kembali',100,'%',20),
  -- Objective 106 — kepatuhan keselamatan
  (1051,106,'Laporan inspeksi fasilitas & K3',4,'Laporan',30),
  (1052,106,'Zero insiden keamanan & keselamatan (LTI)',0,'Kasus',30),
  (1053,106,'Penyelesaian tindak lanjut audit IMS',100,'%',30),
  (1054,106,'Drill simulasi internal GA min 1x/tahun',1,'Kali',10),
  -- Objective 107 — inventaris aset
  (1061,107,'Terlaksananya opname aset 1x',1,'Kali',25),
  (1062,107,'Akurasi opname > 90%',90,'%',25),
  (1063,107,'Database aset GA dengan foto terbaru',100,'%',25),
  (1064,107,'Mutasi & peminjaman barang dengan BAST',100,'%',25),
  -- Objective 108 — kesesuaian pengadaan
  (1071,108,'100% pengadaan sesuai semester di RPBJ',100,'%',30),
  (1072,108,'Pengadaan di luar RPBJ < 30%',30,'%',30),
  (1073,108,'Pembatalan pengadaan sesuai prosedur',100,'%',20),
  (1074,108,'Tidak ada penumpukan pengadaan di Q4',100,'%',20),
  -- Objective 109 — penyediaan kantor pusat
  (1081,109,'Pengadaan vendor konsultan design',100,'%',25),
  (1082,109,'Concept design fitout WN dan TH',100,'%',25),
  (1083,109,'Persetujuan design fitout',100,'%',25),
  (1084,109,'Laporan Space Planning',100,'%',25),
  -- Objective 110 — optimasi perjalanan dinas
  (1091,110,'Protokol Integrasi/Sinkronisasi Workflow',1,'Dokumen',40),
  (1092,110,'Fitur utama (Pemesanan, Approval, Budgeting) deploy',100,'%',40),
  (1093,110,'Dokumentasi project tercatat',100,'%',20),
  -- Objective 111-114 — direct score
  (1101,111,'Realisasi IDP (Skor 0-5)',5,'Skor',100),
  (1111,112,'Skor KM Index (Target 4)',4,'Skor',100),
  (1121,113,'Skor GRC (Target 100%)',100,'%',100),
  (1131,114,'Penyelesaian Audit (Target 100%)',100,'%',100);


-- --- employee_kpi_weights (periode 2026) -----------------------------
-- Total bobot tiap karyawan = 100%.
INSERT INTO `employee_kpi_weights` (`user_id`,`objective_id`,`weight`) VALUES
  -- Rizki Aziz Radyantama (id 1)
  (1,101,10),(1,102,10),(1,103,2.5),(1,104,12.5),(1,106,15),(1,108,10),
  (1,109,15),(1,110,15),(1,111,2.5),(1,112,2.5),(1,113,2.5),(1,114,2.5),
  -- M. Ardhan Rafsanjani (id 2)
  (2,101,10),(2,102,10),(2,103,2.5),(2,104,10),(2,105,10),(2,106,10),
  (2,107,10),(2,108,7.5),(2,109,10),(2,110,10),(2,111,2.5),(2,112,2.5),(2,113,2.5),(2,114,2.5),
  -- Maya Satih Kanteyan (id 3)
  (3,101,10),(3,102,10),(3,103,2.5),(3,104,10),(3,105,10),(3,106,10),
  (3,107,10),(3,108,7.5),(3,109,10),(3,110,10),(3,111,2.5),(3,112,2.5),(3,113,2.5),(3,114,2.5),
  -- Waziruddin (id 4)
  (4,101,10),(4,102,10),(4,103,2.5),(4,104,10),(4,105,10),(4,106,10),
  (4,107,10),(4,108,7.5),(4,109,10),(4,110,10),(4,111,2.5),(4,112,2.5),(4,113,2.5),(4,114,2.5),
  -- Annisa Mayangsari (id 5)
  (5,101,10),(5,102,25),(5,103,2.5),(5,104,20),(5,105,22.5),(5,108,10),
  (5,111,2.5),(5,112,2.5),(5,113,2.5),(5,114,2.5),
  -- Rakhmat (id 6)
  (6,102,20),(6,103,2.5),(6,104,20),(6,106,20),(6,107,10),(6,108,7.5),
  (6,109,10),(6,111,2.5),(6,112,2.5),(6,113,2.5),(6,114,2.5),
  -- Agung Prasetyo Wicaksono (id 7)
  (7,102,20),(7,103,2.5),(7,104,20),(7,106,20),(7,107,10),(7,108,7.5),
  (7,109,10),(7,111,2.5),(7,112,2.5),(7,113,2.5),(7,114,2.5),
  -- Siti Zahratus Solihat (id 8)
  (8,101,20),(8,102,15),(8,103,2.5),(8,104,15),(8,105,20),(8,108,7.5),
  (8,110,10),(8,111,2.5),(8,112,2.5),(8,113,2.5),(8,114,2.5),
  -- Abdul Ajid (id 9)
  (9,102,20),(9,103,2.5),(9,104,25),(9,106,20),(9,107,15),(9,108,7.5),
  (9,111,2.5),(9,112,2.5),(9,113,2.5),(9,114,2.5),
  -- Dharisa Inayah Ramadhan (id 10)
  (10,101,10),(10,102,25),(10,103,2.5),(10,104,20),(10,105,22.5),(10,108,10),
  (10,111,2.5),(10,112,2.5),(10,113,2.5),(10,114,2.5);


-- --- popup_notifications ---------------------------------------------
INSERT INTO `popup_notifications`
  (`id`,`title`,`content`,`target`,`type`,`active`) VALUES
  (1,
   'Selamat Datang di GASS Terus! 👋',
   '<p>Periode <b>KPI 2026</b> sudah aktif. Mohon segera melengkapi penilaian KPI Anda <b>sebelum 31 Desember 2026</b>.</p><p class="mb-0">Hubungi <b>QM Unit</b> jika mengalami kendala.</p>',
   'both','info',1);


-- --- activity_logs (contoh) ------------------------------------------
INSERT INTO `activity_logs` (`user_id`,`action`,`description`) VALUES
  (1,'SYSTEM_INIT','Inisialisasi basis data GASS Terus! versi 2.0.');

-- =====================================================================
--  CATATAN PENGGUNAAN
--
--  1. Skoring KPI berbobot:
--       score_part(KR) = (realisasi / target) * relative_weight
--       total_score    = SUM(score_part)
--  2. Skoring KPI direct (score_type='direct'):
--       rasio          = realisasi / target
--  3. Skor Final (final_sf) ditentukan dari rasio total:
--       rasio >= 1.199  -> 120
--       rasio >  1.001  -> 110
--       rasio >= 0.999  -> 100
--       rasio >= 0.800  ->  90
--       selain itu      ->  80
--  4. Skor Final tertimbang karyawan:
--       SF_karyawan = SUM( final_sf(objective) * weight(objective) / 100 )
--  5. Sebuah submission dapat diedit maksimal 3 kali (edit_count <= 3),
--     setelah itu terkunci.
-- =====================================================================

-- SELESAI
