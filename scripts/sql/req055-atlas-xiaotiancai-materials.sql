PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

UPDATE marketplace_listing_profiles
SET unified_social_credit_code = '91350206699925225K',
    business_license_url = 'https://auth.ai.xmkurt.com/api/business-subjects/2ccb5c43-1f15-491d-b403-cd31d24aaff9/proof-files/18/download',
    contact_name = '翁志海',
    contact_phone = '18950102822',
    contact_email = 'wengzhihai@xmkurt.com',
    registered_address = '中国（福建）自由贸易试验区厦门片区象屿路88号1120室',
    legal_representative_name = '翁志海',
    website_url = 'https://www.xmkurt.com',
    privacy_policy_url = 'https://happylife.ai.impx.net/legal/privacy.html',
    terms_url = 'https://happylife.ai.impx.net/legal/terms.html',
    support_url = 'https://happylife.ai.impx.net',
    icp_record_no = '闽ICP备2024055146号-2',
    copyright_owner = '厦门图灵软件有限公司',
    notes = 'REQ-055：主体资料从用户中心 xmtuling 复用；法人证件、软著和 APP 备案仍按真实缺项管理。',
    updatedat = CURRENT_TIMESTAMP,
    updated_by_user_id = 'codex'
WHERE code = 'xmtuling';

INSERT INTO marketplace_submission_materials
    (Id, material_key, title, material_type, scope_type, scope_code, platform_code, profile_code, content, file_url, metadatajson, reusable, status, expiresat, sortorder, notes, createdat, updatedat, created_by_user_id, updated_by_user_id, proposer_type, proposer_id, proposer_name, handler_type, handler_id, handler_name)
VALUES
    (lower(hex(randomblob(16))), 'company_profile', '发布主体资料', 'company_info', 'profile', 'xmtuling', '', 'xmtuling', '厦门图灵软件有限公司；统一社会信用代码 91350206699925225K；法定代表人翁志海。', '', '{}', 1, 'ready', NULL, 10, '从用户中心企业主体真实同步。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'business_license', '营业执照', 'legal', 'profile', 'xmtuling', '', 'xmtuling', '用户中心主体 xmtuling 的有效营业执照附件。', 'https://auth.ai.xmkurt.com/api/business-subjects/2ccb5c43-1f15-491d-b403-cd31d24aaff9/proof-files/18/download', '{"subjectId":"2ccb5c43-1f15-491d-b403-cd31d24aaff9","proofFileId":18}', 1, 'ready', NULL, 20, '受控引用，不复制证照到公开仓库。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'legal_representative_id', '法定代表人身份证正反面', 'legal', 'profile', 'xmtuling', '', 'xmtuling', '法定代表人翁志海的身份证正反面尚未登记。用户中心现有另一自然人证件不得冒用。', '', '{}', 0, 'missing', NULL, 30, '需翁志海本人受控上传有效证件正反面。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'developer_info', '开发者公司信息', 'company_info', 'profile', 'xmtuling', '', 'xmtuling', '厦门图灵软件有限公司；地址：中国（福建）自由贸易试验区厦门片区象屿路88号1120室；网站：https://www.xmkurt.com。', '', '{}', 1, 'ready', NULL, 40, '主体信息与营业执照保持一致。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'contact_person', '联系人及客服联系方式', 'company_info', 'profile', 'xmtuling', '', 'xmtuling', '联系人：翁志海；电话：18950102822；邮箱：wengzhihai@xmkurt.com。', '', '{}', 1, 'ready', NULL, 50, '从用户中心主体资料真实同步。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统')
ON CONFLICT(scope_type, scope_code, material_key, platform_code) DO UPDATE SET
    title = excluded.title,
    material_type = excluded.material_type,
    profile_code = excluded.profile_code,
    content = excluded.content,
    file_url = excluded.file_url,
    metadatajson = excluded.metadatajson,
    reusable = excluded.reusable,
    status = excluded.status,
    sortorder = excluded.sortorder,
    notes = excluded.notes,
    updatedat = CURRENT_TIMESTAMP,
    updated_by_user_id = 'codex';

INSERT INTO marketplace_submission_materials
    (Id, material_key, title, material_type, scope_type, scope_code, platform_code, profile_code, content, file_url, metadatajson, reusable, status, expiresat, sortorder, notes, createdat, updatedat, created_by_user_id, updated_by_user_id, proposer_type, proposer_id, proposer_name, handler_type, handler_id, handler_name)
VALUES
    (lower(hex(randomblob(16))), 'signed_apk', '正式签名 APK 1.0.0 (100)', 'platform_specific', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '包名 net.impx.happylife.watch；14,677 字节；APK SHA-256 8775bcfe19f9085e0077eab01fc98e9dace4bba873603150f46f591a1f9c4f95；v1/v2 签名有效。', 'https://happylife.ai.impx.net/releases/xiaotiancai/1.0.0/家加分手表积分_1.0.0_100_signed.apk', '{"versionName":"1.0.0","versionCode":100,"sha256":"8775bcfe19f9085e0077eab01fc98e9dace4bba873603150f46f591a1f9c4f95","sizeBytes":14677}', 0, 'ready', NULL, 100, '正式 release 包；私钥未上传。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'app_icon', '应用图标 148 x 148 PNG', 'media', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '148 x 148 PNG，已校验尺寸。', 'https://happylife.ai.impx.net/releases/xiaotiancai/1.0.0/app-icon-148x148.png', '{"width":148,"height":148,"sha256":"233fd9f43b6931c7f198ac2457477e20c435269a656044d1ab473f95c2565416"}', 0, 'ready', NULL, 110, '使用已授权家加分视觉生成。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'app_screenshots', '应用介绍图 320 x 360 PNG（5 张）', 'media', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '绑定、积分首页、申请积分、最近申请、语音输入，共 5 张 320 x 360 PNG；均使用虚构数据。', 'https://happylife.ai.impx.net/releases/xiaotiancai/1.0.0/intro-01-bind.png', '{"count":5,"width":320,"height":360,"baseUrl":"https://happylife.ai.impx.net/releases/xiaotiancai/1.0.0/"}', 0, 'ready', NULL, 120, '符合小天才公开尺寸要求；物理真机原图另列真机证据。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'privacy_policy', '家加分手表积分隐私政策', 'app_info', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '版本 1.0，2026-08-20 生效；覆盖儿童数据、设备绑定、按需麦克风和不保存原始录音。', 'https://happylife.ai.impx.net/legal/privacy.html', '{"version":"1.0","effectiveDate":"2026-08-20"}', 0, 'ready', NULL, 130, '生产 HTTPS 页面已验证 HTTP 200。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'user_agreement', '家加分手表积分用户协议', 'app_info', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '版本 1.0，2026-08-20 生效。', 'https://happylife.ai.impx.net/legal/terms.html', '{"version":"1.0","effectiveDate":"2026-08-20"}', 0, 'ready', NULL, 140, '生产 HTTPS 页面已验证 HTTP 200。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'soft_copyright', '软件著作权登记证书', 'legal', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '用户中心主体及项目历史发布资产未发现与“家加分手表积分”对应的有效软件著作权登记证书。', '', '{}', 0, 'missing', NULL, 150, '必须由版权主管机构签发后补充证书扫描件及登记号。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'copyright_commitment', '版权承诺函定稿（待盖章）', 'legal', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '版权与合规承诺正文已定稿，待公司签署或盖章。', 'https://happylife.ai.impx.net/releases/xiaotiancai/1.0.0/家加分手表积分_首次提交免责函_待盖章.pdf', '{}', 0, 'draft', NULL, 160, '盖章动作必须由主体授权人完成；未盖章不得标记 ready。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'disclaimer', '首次提交免责函定稿（待盖章）', 'legal', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '主体、应用、儿童隐私及权利承诺内容已定稿。', 'https://happylife.ai.impx.net/releases/xiaotiancai/1.0.0/家加分手表积分_首次提交免责函_待盖章.pdf', '{}', 0, 'draft', NULL, 170, '待公司盖章/签署回执。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'test_report', '1.0.0 版本测试报告', 'platform_specific', 'app', 'family-points', 'xiaotiancai', 'xmtuling', 'Release 构建、Android Lint、签名、权限、线上接口和 700 次公网低并发请求已通过；物理小天才真机用例保持待执行。', 'https://happylife.ai.impx.net/releases/xiaotiancai/1.0.0/家加分手表积分_测试报告.pdf', '{"automatedChecks":14,"physicalDeviceStatus":"pending"}', 0, 'draft', NULL, 180, '报告真实可用，但平台若要求真机结论，取得物理设备证据前保持 draft。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'server_performance_report', '首次提交服务器性能报告', 'platform_specific', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '公网 /health 500 次、/watch 200 次，并发 10，合计 700 次请求 0 失败；报告含 P50/P90/P95/P99 与本机回环对照。', 'https://happylife.ai.impx.net/releases/xiaotiancai/1.0.0/家加分手表积分_服务器性能报告.pdf', '{"requests":700,"concurrency":10,"failures":0,"testedAt":"2026-08-20T23:25:00+08:00"}', 0, 'ready', NULL, 190, '生产只读接口受控低负载实测。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'app_filing', 'APP 备案证明', 'legal', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '现有闽ICP备2024055146号-2 为网站 ICP 备案，不能替代移动互联网应用程序备案。', '', '{}', 0, 'missing', NULL, 200, '需主管机构 APP 备案回执或备案号。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'signing_certificate', 'Android 发布签名证书及指纹', 'legal', 'app', 'family-points', 'xiaotiancai', 'xmtuling', 'RSA 4096；证书 SHA-256 61a9f7a203b3a0ab71b89691850b2d646e405ba4ba0dc496363ce6ad62d814b9。', 'https://happylife.ai.impx.net/releases/xiaotiancai/1.0.0/happylife-watch-signing-certificate.pem', '{"algorithm":"RSA 4096","sha256":"61a9f7a203b3a0ab71b89691850b2d646e405ba4ba0dc496363ce6ad62d814b9"}', 0, 'ready', NULL, 210, '公开证书可下载；JKS 与密码仅保存在受限发布存储。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统'),
    (lower(hex(randomblob(16))), 'target_device_matrix', '小天才物理真机兼容矩阵', 'platform_specific', 'app', 'family-points', 'xiaotiancai', 'xmtuling', '已定义方屏、圆屏/特殊安全区、Wi-Fi 和蜂窝网络测试矩阵；尚无目标物理设备型号、系统版本和原始截图。', 'https://happylife.ai.impx.net/releases/xiaotiancai/1.0.0/家加分手表积分_测试报告.pdf', '{"physicalDeviceStatus":"pending"}', 0, 'draft', NULL, 220, '必须在平台确认的真实小天才设备上执行后补签。', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'codex', 'codex', 'agent', 'codex', 'Codex', 'agent', 'agentfree:35', '家庭积分系统')
ON CONFLICT(scope_type, scope_code, material_key, platform_code) DO UPDATE SET
    title = excluded.title,
    material_type = excluded.material_type,
    profile_code = excluded.profile_code,
    content = excluded.content,
    file_url = excluded.file_url,
    metadatajson = excluded.metadatajson,
    reusable = excluded.reusable,
    status = excluded.status,
    sortorder = excluded.sortorder,
    notes = excluded.notes,
    updatedat = CURRENT_TIMESTAMP,
    updated_by_user_id = 'codex';

COMMIT;
