// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get apiRefresh => '刷新';

  @override
  String get apiWorkspace => '工作台';

  @override
  String get apiEmpty => '暂无记录。下拉或点击刷新获取最新状态。';

  @override
  String get apiNewRequest => '提交开发需求';

  @override
  String get apiNewRequestTab => '提交需求';

  @override
  String get apiRequestTitle => '开发需求';

  @override
  String get apiDescription => '目标、使用场景及期望成果';

  @override
  String get apiTiming => '期望完成时间';

  @override
  String get apiPickCompletionDate => '请选择期望完成日期';

  @override
  String get apiBudget => '预算意向（JPY）';

  @override
  String get apiDraftSaved => '草稿已保存到服务端';

  @override
  String get apiSaveDraft => '保存草稿';

  @override
  String get apiSubmitRequest => '提交后台审核';

  @override
  String get apiSubmitted => '需求已提交，等待后台审核';

  @override
  String get apiReviewNotice => '后台完成合规审核与技术整理后才可发布。附件作为客户私有资料保存，发布资料由后台另行确认。';

  @override
  String get apiFiles => '附件与资料';

  @override
  String get apiPickFile => '选择并上传文件';

  @override
  String get apiUploaded => '附件已上传并保存在服务端。需求可附带待检查文件提交；文件通过安全检查后才能预览、下载或用于交付。';

  @override
  String get apiFilePending => '安全检查处理中';

  @override
  String get apiFileReady => '安全检查通过';

  @override
  String get apiFileBlocked => '文件不可用';

  @override
  String get apiFileTooLarge => '请选择不超过 20 MB 的非空文件';

  @override
  String get apiRemoveFile => '移除附件';

  @override
  String get apiRequired => '请填写此项';

  @override
  String get apiDetails => '详情与进展';

  @override
  String get apiVersion => '当前版本';

  @override
  String get apiPendingTerms => '待确认合作条款';

  @override
  String get apiTerms => '合作条款';

  @override
  String get apiTermsConfirmed => '你已确认本版本条款，等待对方确认';

  @override
  String get apiConfirmTerms => '确认当前版本合作条款';

  @override
  String get apiConfirmTermsBody => '确认表示同意下方本版本的范围、报价与交付约定。双方确认后方可提交交付。';

  @override
  String get apiConfirmed => '已确认';

  @override
  String get apiAmount => '报价（JPY）';

  @override
  String get apiDueAt => '期限（JST）';

  @override
  String get apiMessages => '沟通记录';

  @override
  String get apiMessageInput => '填写消息';

  @override
  String get apiSend => '发送';

  @override
  String get apiMessageSent => '消息已发送';

  @override
  String get apiReply => '补充需求';

  @override
  String get apiConsult => '向运营咨询';

  @override
  String get apiConsultNotice => '咨询不会领取任务或建立合作。具体承接关系由后台记录已确认结果。';

  @override
  String get apiDelivery => '交付成果';

  @override
  String get apiOpenDelivery => '提交交付物';

  @override
  String get providerOverview => '我的承接总览';

  @override
  String get providerIntro => '查看沟通、开发与交付进展，前往大厅寻找已发布的任务。';

  @override
  String get providerCommunicating => '沟通中';

  @override
  String get providerDelivered => '已交付';

  @override
  String get providerDeliveredHelp => '已交付包含内部检查、待客户验收及已完成项目，以各项目的实际状态为准。';

  @override
  String get providerHall => '任务大厅';

  @override
  String get providerHallHelp => '仅展示审核通过、已发布且尚未进入合作的任务。';

  @override
  String get providerViewAll => '查看全部';

  @override
  String get negotiationTitle => '合作沟通与条款';

  @override
  String get negotiationStart => '沟通项目';

  @override
  String get negotiationProvider => '承接者';

  @override
  String get negotiationPropose => '提交条款请客户确认';

  @override
  String get negotiationProposed => '条款已提交，等待客户确认';

  @override
  String get negotiationApprove => '确认本次范围与条款';

  @override
  String get negotiationApproveBody =>
      '我已核对本次发布范围、承接者、条款、报价及期限，同意该承接者按此版本承接。确认后仍需承接者点击承接项目。此操作不代表付款。';

  @override
  String get negotiationApproved => '客户已确认本次范围与条款，等待承接者承接';

  @override
  String get negotiationAwaiting => '等待客户确认本次范围与条款';

  @override
  String get negotiationClaim => '承接项目';

  @override
  String get negotiationClaimBody => '确认按客户已确认的当前范围和条款承接项目。项目将归属当前账号并立即进入进行中。';

  @override
  String get negotiationClaimed => '已承接项目，项目已归属本人并开始执行';

  @override
  String get negotiationEdit => '修改条款并重新请客户确认';

  @override
  String get negotiationUnavailable => '该需求已下架或进入合作，不能继续承接。';

  @override
  String get negotiationOutdated => '发布范围已更新，请重新提出当前版本条款并请客户确认。';

  @override
  String get negotiationOptionalAmount => '约定报价（JPY，可不填）';

  @override
  String get negotiationOptionalDue => '选择约定期限（JST 18:00，可不填）';

  @override
  String get negotiationFormError => '请填写条款，报价须为有效的非负整数。';

  @override
  String get apiSubmitDelivery => '提交交付检查';

  @override
  String get apiSourceRepo => '源码仓库 HTTPS 地址';

  @override
  String get apiSourceCommit => '固定提交版本（40 或 64 位 commit SHA）';

  @override
  String get apiSourceFile => '源码归档文件';

  @override
  String get apiSourceArchiveRef => '客户可取得源码的归档证据';

  @override
  String get apiSourceHelp =>
      '填写仓库 HTTPS 地址、完整 commit SHA 和客户可取得源码的归档证据，或选择已通过安全检查的源码归档文件。';

  @override
  String get apiGuide => '操作与部署说明';

  @override
  String get apiTestEvidence => '实际测试命令与结果';

  @override
  String get apiDeliveryNote => '交付说明';

  @override
  String get apiDeliverySubmitted => '交付已保存，等待内部检查后向客户公开';

  @override
  String get apiAccept => '确认验收';

  @override
  String get apiAcceptBody => '确认已查看当前交付版本、源码和操作说明，实际检查符合约定范围。此操作记录验收，不触发付款。';

  @override
  String get apiRevision => '申请修改';

  @override
  String get apiRevisionReason => '具体问题与修改要求';

  @override
  String get apiChanged => '状态已更新';

  @override
  String get apiUnpublishedDelivery => '待内部检查';

  @override
  String get apiPublishedDelivery => '客户可见';

  @override
  String get apiNotifications => '通知';

  @override
  String get apiMarkRead => '标记已读';

  @override
  String get apiNoNotifications => '暂无通知';

  @override
  String get apiProfile => '个人设置';

  @override
  String get apiLogout => '退出登录';

  @override
  String get apiSessionNotice => '重新打开应用需登录。语言偏好保存在本机，业务记录保存在服务端。';

  @override
  String get apiPasswordHelp => '密码重置邮件尚未接入，请联系平台运营协助处理。';

  @override
  String get apiPasswordLength => '注册密码至少 12 位';

  @override
  String get apiFilePreview => '文件预览';

  @override
  String get apiOfficeUnavailable => '当前未接入 Office/PDF 在线转换。可以下载原文件并使用设备应用打开。';

  @override
  String get apiDownload => '下载原文件';

  @override
  String get apiOpenFile => '打开文件';

  @override
  String get apiExportFile => '保存到文件应用';

  @override
  String get apiDownloadDone => '文件已完整保存到应用';

  @override
  String get apiExportDone => '文件已导出';

  @override
  String get apiFileActionFailed => '未完成打开或保存。可重试或选择其他应用。';

  @override
  String get apiRetry => '重试';

  @override
  String get apiCancel => '取消';

  @override
  String get apiLoading => '正在加载…';

  @override
  String get apiNetworkError => '无法连接服务，请检查网络后重试。';

  @override
  String get apiConflict => '记录已被更新。请刷新后核对最新版本再提交。';

  @override
  String get apiForbidden => '当前账号无权执行此操作，请刷新或重新登录。';

  @override
  String get apiUnexpected => '服务暂时不可用，请稍后重试。';

  @override
  String get apiApiSetup =>
      '尚未配置服务地址。请使用 OPC_API_BASE_URL 配置 HTTPS API；本地调试仅允许回环 HTTP。';

  @override
  String get apiDraft => '草稿';

  @override
  String get apiPlay => '播放 / 暂停';

  @override
  String get apiNoPreview => '此格式没有应用内预览，请下载并打开原文件。';

  @override
  String get apiSafetyNotice => '上传后请等待运营安全检查，通过后刷新再提交。未通过检查的文件不会作为正式附件提交。';

  @override
  String get apiScopeIncluded => '包含范围';

  @override
  String get apiScopeExcluded => '不包含范围';

  @override
  String get apiScopeDeliverables => '约定交付物';

  @override
  String get apiScopeAcceptance => '验收标准';

  @override
  String get apiScopeRevision => '修改约定';

  @override
  String get apiWithdrawn => '已撤回';

  @override
  String get apiRejected => '未通过审核';

  @override
  String get apiCancelled => '已取消';

  @override
  String get apiTextTruncated => '此处仅显示文件部分原文，请下载查看完整内容。';

  @override
  String get apiRequestUpdated => '需求已更新';

  @override
  String get apiTermsUpdated => '合作条款已更新，请重新确认';

  @override
  String get apiDeliveryReviewed => '交付内部检查已完成';

  @override
  String get apiDeliveryWithdrawn => '交付已撤回，等待更新';

  @override
  String get apiPublicationWithdrawn => '任务已从大厅撤回';

  @override
  String get apiFileUnavailable => '文件不可访问或尚未通过安全检查，请刷新状态。';

  @override
  String get classificationPlatform => '开发端';

  @override
  String get classificationType => '开发类型';

  @override
  String get classificationAll => '全部';

  @override
  String get classificationUnclassified => '未分类';

  @override
  String get classificationClear => '清除分类筛选';

  @override
  String get classificationOptional => '可选：选择主要开发端及开发类型，未选择时保存为未分类。';

  @override
  String get authDemoAccounts => '体验账号';

  @override
  String get authDemoInfo => '数据为应用内示例，不会实际注册、发送或上传。业务数据会在重启后重置，语言设置会保留。';

  @override
  String get authTryCustomer => '以客户身份体验';

  @override
  String get authTryMember => '以内部承接者身份体验';

  @override
  String get authResetTitle => '重置密码';

  @override
  String get authResetHelp =>
      '体验环境不会发送邮件。体验账号密码为 demo1234。\n\n新注册的账号会在应用重启或重置体验数据后删除。';

  @override
  String get authTheme => '切换主题';

  @override
  String get authEyebrow => 'AI 开发，一起实现';

  @override
  String get authRegisterHero => '让你的想法，\n从这里开始。';

  @override
  String get authLoginHero => '让你的想法，\n成为可用的产品。';

  @override
  String get authIntro => '从需求沟通，到开发与交付。\nOPC 陪你迈出每一步。';

  @override
  String get authNoExpertise => '无需专业知识，也能开始';

  @override
  String get authReviewHelp => '运营团队会审核需求，并整理技术要求。';

  @override
  String get authName => '姓名';

  @override
  String get authNameHint => '请输入姓名';

  @override
  String get authNameRequired => '请输入姓名';

  @override
  String get authEmail => '电子邮箱';

  @override
  String get authEmailInvalid => '请检查电子邮箱格式';

  @override
  String get authPassword => '密码';

  @override
  String get authPasswordNewHint => '请输入至少 8 位密码';

  @override
  String get authPasswordHint => '请输入密码';

  @override
  String get authShowPassword => '显示密码';

  @override
  String get authHidePassword => '隐藏密码';

  @override
  String get authPasswordRequired => '请输入密码（注册时至少 8 位）';

  @override
  String get authForgot => '忘记密码？';

  @override
  String get authBusy => '正在验证…';

  @override
  String get authRegisterSubmit => '注册并开始咨询';

  @override
  String get authLogin => '登录';

  @override
  String get authExisting => '已有账号';

  @override
  String get authNew => '首次使用';

  @override
  String get authBackLogin => '返回登录';

  @override
  String get authRegister => '注册账号并咨询';

  @override
  String get authInternalLogin => '内部承接者也从此处登录';

  @override
  String get authLegalTitle => '服务条款与隐私';

  @override
  String get authLegalHelp =>
      '当前使用示例数据体验。正式服务条款与个人信息处理说明将在上线前提供。请勿输入真实个人信息或机密信息。';

  @override
  String get hallTitle => '任务大厅';

  @override
  String get hallSubtitle => '用你的技术，开启下一个项目';

  @override
  String get hallNotifications => '通知';

  @override
  String get hallInternal => '内部账号';

  @override
  String get hallPublishedWork => '已发布的开发任务';

  @override
  String get hallSearch => '搜索任务关键词';

  @override
  String get hallSort => '最近更新';

  @override
  String get hallEmpty => '暂无符合条件的任务';

  @override
  String get hallEmptyHelp => '请尝试更换关键词或筛选条件。';

  @override
  String get hallPublished => '已发布';

  @override
  String get hallStructured => '需求已整理';

  @override
  String get hallView => '查看详情';

  @override
  String get hallDetail => '任务详情';

  @override
  String get hallDevelopment => '开发服务';

  @override
  String get hallConsult => '咨询此任务';

  @override
  String get hallNotAssigned => '发送咨询不会直接确定项目承接者。';

  @override
  String get hallDuration => '预计开发周期';

  @override
  String get hallMethod => '协作方式';

  @override
  String get hallOnline => '线上协作';

  @override
  String get hallScope => '本次开发内容';

  @override
  String get hallScopeHelp => '具体功能与范围以已发布的说明为基础，与运营团队确认。';

  @override
  String get hallDeliverables => '交付物与验收要点';

  @override
  String get hallFiles => '源代码 / 操作说明 / 测试结果';

  @override
  String get hallIndividualScope => '交付内容与验收要点将按运营团队整理的范围逐项确认。';

  @override
  String get hallPrivateHelp => '详细资料和负责范围请与运营团队沟通确认。未公开的附件不会显示在任务大厅。';

  @override
  String get hallConsultHelp => '请说明你想确认的问题或能够负责的范围，运营团队将另行说明合作确认方式。';

  @override
  String get hallConsultHint => '请输入咨询内容';

  @override
  String get hallConsultRequired => '请输入咨询内容';

  @override
  String get hallSending => '正在发送…';

  @override
  String get hallSend => '发送咨询';

  @override
  String get hallSent => '咨询已发送，项目承接者尚未确定。';

  @override
  String get coreBack => '返回';

  @override
  String get coreBackLogin => '返回登录';

  @override
  String get coreActionFailed => '操作未完成，请重试。';

  @override
  String get coreNeedsInfo => '待补充信息';

  @override
  String get coreReviewing => '审核中';

  @override
  String get corePublished => '已发布';

  @override
  String get coreDeveloping => '开发中';

  @override
  String get coreInternalReview => '内部审核中';

  @override
  String get coreAwaitingAcceptance => '待验收';

  @override
  String get coreRevision => '修改中';

  @override
  String get coreCompleted => '验收完成';

  @override
  String get coreClose => '关闭';

  @override
  String get coreLanguage => '界面语言';

  @override
  String get coreJapanese => '日本語';

  @override
  String get coreChinese => '简体中文';

  @override
  String get coreLanguageSaveFailed => '语言设置保存失败，重启后可能恢复之前的语言。';

  @override
  String get coreSetup => '需要配置服务连接，当前版本仅用于体验。';

  @override
  String get coreAll => '全部';

  @override
  String get coreWeb => 'Web 应用';

  @override
  String get coreAutomation => '业务自动化';

  @override
  String get coreAi => 'AI 开发';

  @override
  String get errorSessionChanged => '账号状态已改变，请重新打开页面。';

  @override
  String get errorNetwork => '体验通信失败，请检查内容后重试。';

  @override
  String get errorUnauthenticated => '请先登录。';

  @override
  String get errorInactive => '此账号已停用。';

  @override
  String get errorCustomer => '请使用客户账号操作。';

  @override
  String get errorProvider => '需要有效的内部承接授权。';

  @override
  String get errorNotFound => '无法查看此项目。';

  @override
  String get errorCredentials => '请检查邮箱或密码。';

  @override
  String get errorName => '请输入不超过 80 字的姓名。';

  @override
  String get errorEmail => '请输入有效的邮箱地址。';

  @override
  String get errorPassword => '密码至少需要 8 位。';

  @override
  String get errorEmailExists => '此邮箱已注册。';

  @override
  String get errorDescription => '请输入 10 至 4,000 字的需求说明。';

  @override
  String get errorRequest => '请选择期望时间和预算意向。';

  @override
  String get errorAttachments => '最多可添加 5 份附件。';

  @override
  String get errorMessage => '请输入 1 至 4,000 字的内容。';

  @override
  String get errorState => '项目状态已改变，请确认最新状态。';

  @override
  String get errorVersion => '请确认当前发布的最新交付版本。';

  @override
  String get errorDelivery => '请填写固定版本源码、操作说明、测试资料和提交说明。';

  @override
  String get errorSource => '请指定源码的固定版本或校验值。';

  @override
  String hallCount(int count) {
    return '开发任务 $count 项';
  }

  @override
  String hallEstimate(String duration) {
    return '预计：$duration';
  }

  @override
  String hallVersion(int version) {
    return '已整理需求 v$version.0';
  }

  @override
  String get customerRequestsTitle => '我的需求';

  @override
  String get customerWorkspaceSubtitle => '客户工作空间';

  @override
  String get customerNotifications => '通知';

  @override
  String get customerHeroTitle => '想实现的创意，\n和我们聊聊吧。';

  @override
  String get customerHeroSubtitle => '不需要专业术语，运营会协助整理您的想法。';

  @override
  String get customerCreateRequest => '咨询开发需求';

  @override
  String get customerContinueDraft => '继续编辑已保存的草稿';

  @override
  String get customerActiveRequests => '进行中的需求';

  @override
  String get customerNoRequests => '暂无需求';

  @override
  String get customerNoRequestsHint => '点击“咨询开发需求”，告诉我们您的创意。';

  @override
  String get customerProgressHint => '可在此查看需求进度';

  @override
  String get customerDraftSaved => '已在本次演示中保存草稿';

  @override
  String get customerAddReference => '添加参考资料';

  @override
  String get customerAttachmentNote => '请选择示例文件名称。当前不会读取设备文件或上传文件。';

  @override
  String get customerAssistTitle => '需求整理建议';

  @override
  String get customerAssistNote => '这是基于设备内固定规则的建议，当前不会发送给 AI 或自动审核。';

  @override
  String get customerKeepOriginal => '使用原文';

  @override
  String get customerAdoptSuggestion => '采用此建议';

  @override
  String get customerConfirmTitle => '确认咨询内容';

  @override
  String get customerFormTitle => '开发咨询';

  @override
  String get customerConfirmSubtitle => '提交前请确认以下内容';

  @override
  String get customerFormSubtitle => '从创意开始，一起实现';

  @override
  String get customerProcessing => '处理中…';

  @override
  String get customerSubmitRequest => '提交咨询';

  @override
  String get customerProceedConfirmation => '前往确认';

  @override
  String get customerEditRequest => '修改内容';

  @override
  String get customerSaveDraft => '保存草稿';

  @override
  String get customerFormStep => '1  咨询内容';

  @override
  String get customerConfirmStep => '2  确认内容';

  @override
  String get customerServiceCategory => '开发 · AI 开发系统';

  @override
  String get customerGoalLabel => '希望实现的目标';

  @override
  String get customerTimingLabel => '期望时间';

  @override
  String get customerBudgetLabel => '预算意向';

  @override
  String get customerReferenceLabel => '参考资料';

  @override
  String get customerNoAttachments => '无资料';

  @override
  String get customerConfirmNotice =>
      '运营会审核合规性并整理技术需求，提交后不会直接发布到任务大厅。预算仅代表您的意向，此时不会产生付款。';

  @override
  String get customerFormIntro => '还处于创意阶段也没关系。\n请用自己的话告诉我们，您希望实现什么。';

  @override
  String get customerGoalQuestion => '您希望实现什么？';

  @override
  String get customerRequired => '必填';

  @override
  String get customerGoalHint => '请描述您希望实现的目标';

  @override
  String get customerGoalValidation => '请至少输入 10 个字描述希望实现的目标';

  @override
  String get customerAssistAction => '使用 AI 整理咨询内容';

  @override
  String get customerOptionalReference => '参考资料（选填）';

  @override
  String get customerAddFiles => '添加资料或图片';

  @override
  String get customerSampleReference => '示例资料';

  @override
  String get customerSubmitNotice => '提交后由运营审核并整理内容。\n此时不会发布到任务大厅。';

  @override
  String get customerReviewTitle => '需求审核进度';

  @override
  String get customerReviewSubtitle => '运营正在审核并整理您的需求';

  @override
  String get customerReplyAction => '回复问题';

  @override
  String get customerBackToRequests => '返回需求列表';

  @override
  String get customerPublished => '已发布';

  @override
  String get customerUnderReview => '内容审核中';

  @override
  String get customerReviewSteps => '发布流程';

  @override
  String get customerReceivedStep => '已受理需求';

  @override
  String get customerReceivedStepDetail => '已收到您的需求';

  @override
  String get customerComplianceStep => '合规审核';

  @override
  String get customerComplianceComplete => '运营已完成合规审核';

  @override
  String get customerCompliancePending => '请等待运营审核';

  @override
  String get customerRequirementsStep => '整理技术需求';

  @override
  String get customerRequirementsComplete => '已完成技术需求整理';

  @override
  String get customerRequirementsNeedsInfo => '等待您补充信息';

  @override
  String get customerRequirementsPending => '运营将审核并整理内容';

  @override
  String get customerPublicationStep => '发布到任务大厅';

  @override
  String get customerPublicationComplete => '已发布审核通过的版本';

  @override
  String get customerPublicationPending => '所有审核完成后发布';

  @override
  String get customerOperatorQuestion => '运营需要确认的信息';

  @override
  String get customerOperatorAwaitingReply => 'OPC 运营 · 等待您的回复';

  @override
  String get customerOperatorReplyReceived => 'OPC 运营 · 已收到回复';

  @override
  String get customerSupplementConversation => '补充与沟通';

  @override
  String get customerPublicationNotice => '只有审核通过并发布的版本才会出现在任务大厅。';

  @override
  String get customerUnpublishedNotice => '此需求尚未发布到任务大厅。';

  @override
  String get customerReplySuccess => '回复已发送，请等待运营确认。';

  @override
  String get customerReplyLabel => '您的回复';

  @override
  String get customerReplyHint => '例如：使用者约 30 人，参考资料为 PDF。';

  @override
  String get customerReplyValidation => '请输入回复内容';

  @override
  String get customerReplyNotice => '回复将由运营确认，发送后不会自动完成审核或发布。';

  @override
  String get customerSending => '发送中…';

  @override
  String get customerSendReply => '发送回复';

  @override
  String get customerRequestDetail => '需求详情';

  @override
  String get customerNoNotifications => '暂无新通知。';

  @override
  String get customerWorkspace => '工作空间';

  @override
  String get customerTasks => '任务';

  @override
  String get customerHome => '首页';

  @override
  String get customerProjects => '项目';

  @override
  String get customerRequests => '需求';

  @override
  String get customerMessages => '消息';

  @override
  String get customerProfile => '我的';

  @override
  String get customerMessageListSubtitle => '按需求查看沟通记录';

  @override
  String get customerRequestListSubtitle => '随时查看进度';

  @override
  String get customerEmptyWorkspace => '暂无需求。请从首页发起开发咨询。';

  @override
  String get customerViewDetails => '查看详情';

  @override
  String get customerSendMessage => '发送';

  @override
  String get customerMessageSent => '消息已发送';

  @override
  String get customerConversationNote => '此处用于与运营沟通当前需求。';

  @override
  String get customerNoMessages => '暂无消息。';

  @override
  String get customerMessageHint => '输入消息';

  @override
  String get customerProfileSubtitle => '账号与显示设置';

  @override
  String get customerInternalAccount => '内部账号';

  @override
  String get customerCustomerAccount => '客户账号';

  @override
  String get customerInternalAuthorization => '已获得内部任务处理权限，这不代表已通过 OPC 正式认证。';

  @override
  String get customerAppearance => '显示设置';

  @override
  String get customerThemeSystem => '跟随系统';

  @override
  String get customerThemeLight => '浅色';

  @override
  String get customerThemeDark => '深色';

  @override
  String get customerBusinessRegion => '日本业务 · 日元（JPY）· 日本标准时间（JST）';

  @override
  String get customerAbout => '关于应用';

  @override
  String get customerAboutNote =>
      'OPC V1 / 0.1.0\n当前为演示环境，业务数据保存在设备内存中，重启应用后恢复初始状态。尚未连接真实身份认证、文件上传或支付服务。';

  @override
  String get customerDemoScenarios => '演示场景';

  @override
  String get customerLogout => '退出登录';

  @override
  String get customerDemoSubtitle => '演示操作 · 不执行真实管理操作';

  @override
  String get customerDemoNotice => '以下开发操作用于演示后台审核结果。正式业务中仅由管理端与服务端执行审核和发布。';

  @override
  String get customerSimulateDelivery => '演示内部审核后发布交付';

  @override
  String get customerSimulatePublication => '演示审核并整理需求后发布';

  @override
  String get customerDemoUpdated => '已更新演示状态';

  @override
  String get customerFailNextAction => '模拟下一次发送失败';

  @override
  String get customerFailNextNotice => '下一次发送将模拟失败，可保留内容并重试。';

  @override
  String get customerResetDemo => '恢复演示初始状态';

  @override
  String get customerResetDemoTitle => '重置演示数据？';

  @override
  String get customerResetDemoNotice => '将删除本次演示中新增的账号、需求和消息，并返回登录页面。';

  @override
  String get customerBack => '返回';

  @override
  String get customerReset => '重置';

  @override
  String customerRequestCount(int count) {
    return '$count 项';
  }

  @override
  String customerDeliveryPrompt(String id) {
    return '$id · 请确认交付内容';
  }

  @override
  String customerRemoveAttachment(String name) {
    return '删除 $name';
  }

  @override
  String customerAssistedDescription(String original) {
    return '希望实现的目标：\n$original\n\n使用者：公司内部员工（人数在咨询时确认）\n需要确认：所用资料的格式、所需功能、完成后的运行维护方式。';
  }

  @override
  String customerReceivedDate(int year, int month, int day, String time) {
    return '$year年$month月$day日 $time（JST）';
  }

  @override
  String customerReceivedAt(String date) {
    return '受理时间：$date';
  }

  @override
  String customerMessageDate(int month, int day, String time) {
    return '$month月$day日 $time JST';
  }

  @override
  String get customerTimingMonth => '希望 1 个月内';

  @override
  String get customerTimingQuarter => '希望 2～3 个月内';

  @override
  String get customerTimingDiscuss => '希望协商时间';

  @override
  String get customerBudgetDiscuss => '希望协商决定';

  @override
  String get customerBudgetUnder100k => '不足 10 万日元';

  @override
  String get customerBudget100to300k => '10 万～30 万日元';

  @override
  String get customerBudget300to500k => '30 万～50 万日元';

  @override
  String get customerBudgetOver500k => '50 万日元以上';

  @override
  String get customerLanguage => '语言';

  @override
  String get customerLanguageNote => '仅切换界面语言，不自动翻译需求或消息原文，也不改变货币、时间和权限。';

  @override
  String get fileSaveToPhone => '保存到手机文件';

  @override
  String get filePreviewFailed => '暂时无法预览。可以重试，或将原文件保存到手机后打开。';

  @override
  String get fileInlineAttachment => '查看文件';

  @override
  String get fileOriginal => '下载原文件';

  @override
  String get mediaFullscreen => '全屏播放';

  @override
  String get mediaExitFullscreen => '退出全屏';

  @override
  String get mediaPause => '暂停';

  @override
  String get mediaReplay => '重新播放';

  @override
  String get mediaBackward => '快退 10 秒';

  @override
  String get mediaForward => '快进 10 秒';

  @override
  String get mediaMute => '静音';

  @override
  String get mediaUnmute => '恢复声音';

  @override
  String get mediaSpeed => '播放速度';

  @override
  String get homeIntro => '你的需求、项目进展与合作动态';

  @override
  String homeGreeting(String name) {
    return '$name，你好';
  }

  @override
  String get homeOverview => '我的项目总览';

  @override
  String homeSummary(int requests, int projects) {
    return '$requests 项需求 · $projects 个合作项目';
  }

  @override
  String get homeReviewing => '审核中';

  @override
  String get homeActive => '进行中';

  @override
  String get homeAcceptance => '待验收';

  @override
  String get homeCompleted => '已完成';

  @override
  String get homeAll => '查看全部';

  @override
  String get homeClearFilter => '显示全部需求';

  @override
  String get homeTodos => '需要你处理';

  @override
  String get homeNoTodos => '目前没有需要你处理的事项';

  @override
  String get homeNoTodosHelp => '审核、条款或交付需要你确认时，会集中显示在这里。';

  @override
  String get homeReplyHelp => '运营有问题需要你补充，回复后可继续推进。';

  @override
  String get homeAgreementHelp => '请核对范围、报价与交付约定，确认当前版本条款。';

  @override
  String get homeAcceptanceHelp => '交付成果已向你开放，请查看并验收或提出修改。';

  @override
  String get homeReviews => '需求审核与发布';

  @override
  String get homeNoReviews => '暂无待审核或待合作的需求';

  @override
  String get homeReviewHelp => '运营正在审核需求并整理技术范围。';

  @override
  String get homePublishedHelp => '需求已发布，等待确认合作关系。';

  @override
  String get homeProjects => '项目进度';

  @override
  String get homeNoProjects => '暂无推进中的合作项目';

  @override
  String get homeNoProjectsHelp => '确定合作后，可在这里查看当前阶段、交付期限与反馈。';

  @override
  String get homeStageReview => '需求审核';

  @override
  String get homeStageAgreement => '合作确认';

  @override
  String get homeStageDevelopment => '开发交付';

  @override
  String get homeStageAcceptance => '客户验收';

  @override
  String get homeWorkingHelp => '承接者正在按约定范围推进，可进入项目查看沟通和成果。';

  @override
  String get homeInternalHelp => '成果正在内部检查，向你开放后即可查看并验收。';

  @override
  String get homeRevisionHelp => '承接者正在处理修改，请在沟通记录中跟进。';

  @override
  String get homeFeedback => '承接者最近反馈';

  @override
  String get homeNoFeedback => '暂无承接者反馈';

  @override
  String get homeNoFeedbackHelp => '项目承接者发来的消息会汇总在这里。';

  @override
  String get homeProvider => '项目承接者';

  @override
  String homeUnread(int count) {
    return '$count 条未读通知';
  }

  @override
  String get homeStart => '从第一个需求开始';

  @override
  String get homeStartHelp => '告诉我们你想解决的问题。提交后可在这里跟踪审核、开发与交付。';

  @override
  String get homeDraft => '继续填写已保存的需求';

  @override
  String get homeMoreTodos => '查看全部待办';

  @override
  String get previewTitle => '资料预览';

  @override
  String get previewImageTitle => '查看图片';

  @override
  String get previewVideoTitle => '播放视频';

  @override
  String get previewDocumentTitle => '文档预览';

  @override
  String get previewPdfTitle => 'PDF 预览';

  @override
  String get previewTableTitle => '表格预览';

  @override
  String get previewSlidesTitle => '幻灯片预览';

  @override
  String get previewTextTitle => '文本预览';

  @override
  String get previewReadOnly => '只读';

  @override
  String get previewPrevious => '上一项';

  @override
  String get previewNext => '下一项';

  @override
  String get previewZoomIn => '放大';

  @override
  String get previewZoomOut => '缩小';

  @override
  String get previewResetZoom => '重置缩放';

  @override
  String get previewImageHint => '双指缩放；未放大时可左右滑动，也可通过箭头或缩略图切换图片。';

  @override
  String get previewPages => '跳转页面';

  @override
  String get previewPageNumber => '页码';

  @override
  String get previewGo => '跳转';

  @override
  String get previewCancel => '取消';

  @override
  String get previewDocumentHint => '上下滚动阅读，点击页码可以跳转。';

  @override
  String get previewFixtureNotice => '当前显示内置示例资料，尚未接入任意 Office 文件转换服务。';

  @override
  String get previewFullscreen => '全屏';

  @override
  String get previewExitFullscreen => '退出全屏';

  @override
  String get previewSlideHint => '通过前后按钮或缩略图切换幻灯片。';

  @override
  String get previewOriginal => '原文';

  @override
  String get previewFormatted => '排版';

  @override
  String get previewTextSize => '字号';

  @override
  String get previewSmallerText => '缩小字号';

  @override
  String get previewLargerText => '增大字号';

  @override
  String get previewTextHint => '内容保持原文。TXT 自动换行，Markdown 支持标题、列表、代码等基本格式。';

  @override
  String get previewSearch => '搜索表格';

  @override
  String get previewClearSearch => '清除搜索';

  @override
  String get previewNoMatches => '未找到匹配单元格。';

  @override
  String get previewTableHint => '左右滚动查看各列，CSV 显示为单个表格。';

  @override
  String get previewPlay => '播放';

  @override
  String get previewPause => '暂停';

  @override
  String get previewMute => '静音';

  @override
  String get previewUnmute => '取消静音';

  @override
  String get previewSeek => '播放进度';

  @override
  String get previewVideoLoading => '正在加载视频';

  @override
  String get previewVideoFailed => '视频播放失败';

  @override
  String get previewVideoHint => '点击后播放，不会自动播放。';

  @override
  String get previewPreparing => '正在准备预览';

  @override
  String get previewPreparingHint => '可以下载原文件，也可以重新检查预览准备状态。';

  @override
  String get previewCheckPreparation => '检查准备状态';

  @override
  String get previewFailed => '预览失败';

  @override
  String get previewFailedHint => '请重试，或下载原文件查看。';

  @override
  String get previewRetry => '重试';

  @override
  String get previewUnsupported => '暂不支持预览';

  @override
  String get previewUnsupportedHint => '可以下载原文件查看。';

  @override
  String get previewAccessDenied => '无权访问此资料';

  @override
  String get previewAccessDeniedHint => '已停止查看。如需访问，请联系运营人员。';

  @override
  String get previewEmpty => '暂无可显示内容';

  @override
  String get previewImageFailed => '图片加载失败';

  @override
  String get previewSelectedCell => '所选单元格';

  @override
  String previewImageCount(int current, int total) {
    return '图片 $current / $total';
  }

  @override
  String previewPageCount(int current, int total) {
    return '$current / $total';
  }

  @override
  String previewPageRange(int total) {
    return '请输入 1 至 $total 的页码';
  }

  @override
  String previewSearchMatches(int count) {
    return '匹配 $count 个单元格';
  }

  @override
  String previewSheetCount(int count) {
    return '$count 个工作表';
  }

  @override
  String previewThumbnail(int index) {
    return '打开第 $index 页';
  }

  @override
  String get projectTitle => '项目';

  @override
  String get projectProviderSubtitle => '负责项目的工作空间';

  @override
  String get projectCustomerSubtitle => '查看您的需求进度';

  @override
  String get projectInfoTitle => '项目信息';

  @override
  String get projectInternalReviewPending => '运营正在确认提交内容，尚未向客户公开。';

  @override
  String get projectAwaitingOperations => '等待运营确认';

  @override
  String get projectSubmitRevision => '提交修订版';

  @override
  String get projectSubmitDelivery => '提交交付成果';

  @override
  String get projectReviewDelivery => '查看交付内容';

  @override
  String get projectSendMessage => '发送消息';

  @override
  String get projectConsultation => '项目沟通';

  @override
  String get projectConsultationHint => '如有需要确认的事项，请通过消息告诉我们。';

  @override
  String get projectOpenMessages => '打开消息';

  @override
  String get projectNoMessages => '暂无消息。';

  @override
  String get projectNoProviderDeliveries => '尚未提交交付成果，可通过下方按钮提交。';

  @override
  String get projectNoCustomerDeliveries => '面向客户的交付文件将在运营确认后显示。';

  @override
  String get projectEditFixedVersion => '编辑固定版本';

  @override
  String get projectFixedVersion => '发布版本／固定提交';

  @override
  String get projectFixedVersionHint => '例如：v0.3.0 · 8f3a2c1';

  @override
  String get projectFixedVersionHelp => '请输入可确定本次源码的标签或提交标识。这是示例记录。';

  @override
  String get projectSave => '保存';

  @override
  String get projectSubmitted => '已请求运营确认，内部确认后才会向客户公开。';

  @override
  String get projectDeliveryTitle => '提交交付成果';

  @override
  String get projectDeliveryUnauthorized => '仅本项目负责人可以提交交付成果。';

  @override
  String get projectDeliverySubtitle => '整理成果，便于检查与确认';

  @override
  String get projectSubmitting => '正在提交…';

  @override
  String get projectRequestReview => '请求运营确认';

  @override
  String get projectSourceCode => '源代码';

  @override
  String get projectRequired => '必填';

  @override
  String get projectSourceSelected => '18.4 MB · 已选择';

  @override
  String get projectGuideAndTest => '操作说明与验证资料';

  @override
  String get projectGuideSelected => '1.2 MB · 已选择';

  @override
  String get projectTestSelected => '84 KB · 已选择';

  @override
  String get projectChanges => '本次变更';

  @override
  String get projectChangesHint => '请输入变更内容与验证方法';

  @override
  String get projectChangesRequired => '请输入变更内容';

  @override
  String get projectDeliveryReviewNotice => '提交后，运营将确认内容。\n内部确认后才会向客户公开。';

  @override
  String get projectAttachmentsNotice => '附件仅为示例文件名，不会上传真实文件或执行测试。';

  @override
  String get projectAcceptConfirmTitle => '确认完成验收？';

  @override
  String get projectBack => '返回';

  @override
  String get projectCompleteAcceptance => '完成验收';

  @override
  String get projectAccepted => '验收已完成，感谢您的确认。';

  @override
  String get projectRequestRevision => '申请修改';

  @override
  String get projectRevisionContent => '需要修改的内容';

  @override
  String get projectRevisionHint => '请说明相关页面、操作步骤和预期结果';

  @override
  String get projectRevisionHelp => '运营将确认您的修改申请。申请后请等待新的公开版本。';

  @override
  String get projectRevisionRequested => '修改申请已记录，运营将确认内容。';

  @override
  String get projectAcceptanceTitle => '确认交付内容';

  @override
  String get projectNoPublishedDelivery => '尚无向客户公开的交付内容，运营确认后将显示。';

  @override
  String get projectAcceptanceSubtitle => '请亲自检查交付成果';

  @override
  String get projectAcceptedNotice => '公开版本已完成验收。';

  @override
  String get projectRevisionPendingNotice => '已收到修改申请，请等待新的公开版本。';

  @override
  String get projectCheckAllHint => '确认所有检查项后，即可完成验收。';

  @override
  String get projectAcceptanceComplete => '验收完成';

  @override
  String get projectWatchDemo => '查看操作演示';

  @override
  String get projectDemoSummary => '了解从登记到处理完成的操作';

  @override
  String get projectPublishedFiles => '交付文件与操作说明';

  @override
  String get projectPublishedFileCount => '公开版本资料 3 份';

  @override
  String get projectAcceptanceChecklist => '请确认以下事项';

  @override
  String get projectRevisionReviewing => '运营正在确认您的修改申请。';

  @override
  String get projectAcceptedFilesNotice => '感谢您的确认，您仍可在此页面查看交付文件。';

  @override
  String get projectRevisionInvitation => '如有问题，请通过申请修改告诉我们，运营将确认内容。';

  @override
  String get projectProgressTab => '进度';

  @override
  String get projectMessagesTab => '消息';

  @override
  String get projectFilesTab => '文件';

  @override
  String get projectMilestones => '里程碑';

  @override
  String get projectRequirementsMilestone => '需求确认';

  @override
  String get projectDevelopmentMilestone => '开发';

  @override
  String get projectInternalMilestone => '内部确认';

  @override
  String get projectCustomerMilestone => '客户确认';

  @override
  String get projectRevisionMilestoneDescription => '确认您申请的修改内容';

  @override
  String get projectRequirementsMilestoneDescription => '确定范围与验收标准';

  @override
  String get projectDevelopmentMilestoneDescription => '正在实现搜索页面与回答功能';

  @override
  String get projectInternalMilestoneDescription => '运营检查质量与资料';

  @override
  String get projectCustomerMilestoneDescription => '验收已公开的交付内容';

  @override
  String get projectMessageAvatar => '讯';

  @override
  String get projectReplaceFile => '替换文件';

  @override
  String get projectDeliveryPublished => '已向客户公开';

  @override
  String get projectDeliveryInternal => '用于内部确认';

  @override
  String get projectGuideMetadata => '操作说明';

  @override
  String get projectTestMetadata => '验证资料';

  @override
  String get projectMessageSent => '消息已发送';

  @override
  String get projectMessageHint => '输入消息';

  @override
  String get projectMessageRequired => '请输入消息';

  @override
  String get projectMessageSendTooltip => '发送消息';

  @override
  String get projectSelectFile => '选择文件';

  @override
  String get projectFilePickerNotice => '可以选择或编辑示例名称，不会发送真实文件。';

  @override
  String get projectSampleFilename => '示例文件名';

  @override
  String get projectFilenameRequired => '请输入文件名';

  @override
  String get projectUseSample => '使用此示例';

  @override
  String get projectCancel => '取消';

  @override
  String get projectClose => '关闭';

  @override
  String get projectSourcePreview =>
      '完整源代码\n\n・应用程序源码\n・环境配置示例\n・启动说明（README）\n\n这是与固定版本关联的结构示例，此页面不会执行或下载代码。';

  @override
  String get projectGuidePreview =>
      '操作说明示例\n\n1. 在列表页查看已登记的项目。\n2. 输入关键词进行搜索。\n3. 在详情页查看并更新内容。\n4. 保存后，返回列表查看变更结果。';

  @override
  String get projectTestPreview =>
      '验证资料示例\n\n・登记与搜索场景\n・更新与保存场景\n・操作说明检查\n\n此资料是用于界面验证的合成数据，不代表实际测试结果或质量保证。';

  @override
  String get projectFileAccessNotice => '真实文件的获取与分发将在后续接入 API 时实现。';

  @override
  String get projectDemoTitle => '操作演示';

  @override
  String get projectDemoRegister => '1. 登记咨询';

  @override
  String get projectDemoSearch => '2. 从列表搜索';

  @override
  String get projectDemoUpdate => '3. 更新处理状态';

  @override
  String get projectDemoRegisterDescription => '输入主题与内容并保存后，列表中将显示新的咨询。';

  @override
  String get projectDemoSearchDescription => '使用关键词筛选并查看咨询详情。';

  @override
  String get projectDemoUpdateDescription => '更改负责人和处理状态，保存后在列表中查看结果。';

  @override
  String get projectDemoRestart => '从头查看';

  @override
  String get projectDemoNext => '下一步操作';

  @override
  String get projectDemoNotice => '这是页面内的示例指南，未连接真实交付环境或视频。';

  @override
  String get projectInfoMessageNotice => '如有变更或疑问，请通过项目消息沟通。';

  @override
  String get projectNextDeveloping => '下一步：10月16日 确认演示';

  @override
  String get projectNextInternalReview => '下一步：运营确认内容';

  @override
  String get projectNextAcceptance => '下一步：客户确认交付内容';

  @override
  String get projectNextRevision => '下一步：确认修改内容并重新提交';

  @override
  String get projectNextCompleted => '公开版本已完成验收';

  @override
  String get projectNextDefault => '将根据进度告知下一步安排';

  @override
  String get projectCheckFaqSearch => '可以输入问题并搜索相关资料';

  @override
  String get projectCheckFaqSources => '可以查看回答依据的资料';

  @override
  String get projectCheckGuide => '已阅读操作说明并确认使用方法';

  @override
  String get projectCheckSearch => '可以登记和搜索咨询';

  @override
  String get projectCheckUpdate => '可以更新负责人和处理状态';

  @override
  String projectSubmissionDestination(String id) {
    return '$id · 提交至：OPC 运营';
  }

  @override
  String projectAcceptConfirmBody(int version) {
    return '即将完成公开版 v$version.0.0 的确认。\n\n此操作仅记录交付验收，不会付款或结算。';
  }

  @override
  String projectCustomerVersion(int version) {
    return '面向客户的公开版 v$version.0.0';
  }

  @override
  String projectSubmittedVersion(int version) {
    return '提交版本 $version';
  }

  @override
  String projectFieldRequired(String label) {
    return '请输入$label';
  }

  @override
  String projectTargetVersion(String version) {
    return '目标版本：$version';
  }

  @override
  String projectDemoVersion(String version) {
    return '公开版 $version · 示例指南';
  }

  @override
  String projectConfirmedScope(int version) {
    return '已确认的范围：版本 $version';
  }

  @override
  String get refTitle => '参考资料';

  @override
  String refPublishedVersion(String taskId, int version) {
    return '$taskId · 已发布需求 v$version.0';
  }

  @override
  String get refPublishedNotice => '仅展示当前已发布需求版本中的参考资料。';

  @override
  String refViewAll(int count) {
    return '查看全部 $count';
  }

  @override
  String refImages(int count) {
    return '图片 $count';
  }

  @override
  String refVideos(int count) {
    return '视频 $count';
  }

  @override
  String refFiles(int count) {
    return '附件 $count';
  }

  @override
  String get refImageHint => '界面参考';

  @override
  String get refVideoHint => '操作参考';

  @override
  String get refAttachments => '附件文件';

  @override
  String refCount(int count) {
    return '$count 份';
  }

  @override
  String get refOpenHint => '点击查看或播放，所有资料均可单独保存。';

  @override
  String get refEmpty => '暂无已公开的参考资料。';

  @override
  String get refPreview => '预览';

  @override
  String get refDownload => '下载原文件';

  @override
  String get refImageDownload => '下载图片';

  @override
  String get refVideoDownload => '下载视频';

  @override
  String refDownloading(int percent) {
    return '正在下载 · $percent%';
  }

  @override
  String get refCancel => '取消';

  @override
  String get refCancelled => '已取消下载';

  @override
  String get refDownloadFailed => '下载失败';

  @override
  String get refRetry => '重试';

  @override
  String get refDownloaded => '下载完成';

  @override
  String get refSavedInApp => '已保存到应用内。如需保存到手机文件，请选择“导出”。';

  @override
  String get refLocalSample => '将保存应用内附带的示例原文件。';

  @override
  String get refOpen => '打开';

  @override
  String get refExport => '导出';

  @override
  String get refActionFailed => '打开或导出文件未完成，请检查可用应用或保存位置。';

  @override
  String get refAccessDenied => '你没有访问此资料的权限，如有需要请联系运营人员。';

  @override
  String get refScenarios => '资料显示状态';

  @override
  String get refScenarioHelp => '使用已发布的示例资料检查各种显示状态，不改变资料或账号的访问权限。';

  @override
  String get refReady => '可以预览';

  @override
  String get refPreparing => '正在准备预览';

  @override
  String get refPreviewFailed => '预览失败';

  @override
  String get refUnsupported => '暂不支持预览';

  @override
  String get refDownloadFailureCase => '下载失败与重试';

  @override
  String get refDownloadCancelCase => '下载进度与取消';
}
