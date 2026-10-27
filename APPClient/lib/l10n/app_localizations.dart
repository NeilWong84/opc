import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @apiRefresh.
  ///
  /// In ja, this message translates to:
  /// **'更新'**
  String get apiRefresh;

  /// No description provided for @apiWorkspace.
  ///
  /// In ja, this message translates to:
  /// **'ワークスペース'**
  String get apiWorkspace;

  /// No description provided for @apiEmpty.
  ///
  /// In ja, this message translates to:
  /// **'記録がありません。更新して最新の状態を確認できます。'**
  String get apiEmpty;

  /// No description provided for @apiNewRequest.
  ///
  /// In ja, this message translates to:
  /// **'開発の相談を送る'**
  String get apiNewRequest;

  /// No description provided for @apiNewRequestTab.
  ///
  /// In ja, this message translates to:
  /// **'依頼する'**
  String get apiNewRequestTab;

  /// No description provided for @apiRequestTitle.
  ///
  /// In ja, this message translates to:
  /// **'開発の相談'**
  String get apiRequestTitle;

  /// No description provided for @apiDescription.
  ///
  /// In ja, this message translates to:
  /// **'目的・利用場面・希望する成果'**
  String get apiDescription;

  /// No description provided for @apiTiming.
  ///
  /// In ja, this message translates to:
  /// **'希望完了日'**
  String get apiTiming;

  /// No description provided for @apiPickCompletionDate.
  ///
  /// In ja, this message translates to:
  /// **'希望完了日を選択してください'**
  String get apiPickCompletionDate;

  /// No description provided for @apiBudget.
  ///
  /// In ja, this message translates to:
  /// **'予算の希望（JPY）'**
  String get apiBudget;

  /// No description provided for @apiDraftSaved.
  ///
  /// In ja, this message translates to:
  /// **'下書きをサーバーに保存しました'**
  String get apiDraftSaved;

  /// No description provided for @apiSaveDraft.
  ///
  /// In ja, this message translates to:
  /// **'下書きを保存'**
  String get apiSaveDraft;

  /// No description provided for @apiSubmitRequest.
  ///
  /// In ja, this message translates to:
  /// **'運営の審査に提出'**
  String get apiSubmitRequest;

  /// No description provided for @apiSubmitted.
  ///
  /// In ja, this message translates to:
  /// **'相談を提出しました。運営の審査をお待ちください'**
  String get apiSubmitted;

  /// No description provided for @apiReviewNotice.
  ///
  /// In ja, this message translates to:
  /// **'コンプライアンス審査と技術整理が完了した後に公開されます。添付は非公開資料として保存され、公開資料は運営が別途確認します。'**
  String get apiReviewNotice;

  /// No description provided for @apiFiles.
  ///
  /// In ja, this message translates to:
  /// **'添付資料'**
  String get apiFiles;

  /// No description provided for @apiPickFile.
  ///
  /// In ja, this message translates to:
  /// **'ファイルを選んでアップロード'**
  String get apiPickFile;

  /// No description provided for @apiUploaded.
  ///
  /// In ja, this message translates to:
  /// **'添付はサーバーに保存されています。安全確認待ちの添付付きで相談を提出できます。確認完了後にプレビュー・ダウンロード・納品への利用が可能になります。'**
  String get apiUploaded;

  /// No description provided for @apiFilePending.
  ///
  /// In ja, this message translates to:
  /// **'安全確認待ち'**
  String get apiFilePending;

  /// No description provided for @apiFileReady.
  ///
  /// In ja, this message translates to:
  /// **'安全確認済み'**
  String get apiFileReady;

  /// No description provided for @apiFileBlocked.
  ///
  /// In ja, this message translates to:
  /// **'利用できないファイル'**
  String get apiFileBlocked;

  /// No description provided for @apiFileTooLarge.
  ///
  /// In ja, this message translates to:
  /// **'20 MB 以下の空でないファイルを選択してください'**
  String get apiFileTooLarge;

  /// No description provided for @apiRemoveFile.
  ///
  /// In ja, this message translates to:
  /// **'添付を外す'**
  String get apiRemoveFile;

  /// No description provided for @apiRequired.
  ///
  /// In ja, this message translates to:
  /// **'入力してください'**
  String get apiRequired;

  /// No description provided for @apiDetails.
  ///
  /// In ja, this message translates to:
  /// **'詳細と進捗'**
  String get apiDetails;

  /// No description provided for @apiVersion.
  ///
  /// In ja, this message translates to:
  /// **'現在のバージョン'**
  String get apiVersion;

  /// No description provided for @apiPendingTerms.
  ///
  /// In ja, this message translates to:
  /// **'協業条件の確認待ち'**
  String get apiPendingTerms;

  /// No description provided for @apiTerms.
  ///
  /// In ja, this message translates to:
  /// **'協業条件'**
  String get apiTerms;

  /// No description provided for @apiTermsConfirmed.
  ///
  /// In ja, this message translates to:
  /// **'この条件を確認済みです。相手の確認をお待ちください'**
  String get apiTermsConfirmed;

  /// No description provided for @apiConfirmTerms.
  ///
  /// In ja, this message translates to:
  /// **'現在の協業条件に同意'**
  String get apiConfirmTerms;

  /// No description provided for @apiConfirmTermsBody.
  ///
  /// In ja, this message translates to:
  /// **'表示中のバージョンの範囲・見積・納品条件に同意します。双方の確認後に納品を提出できます。'**
  String get apiConfirmTermsBody;

  /// No description provided for @apiConfirmed.
  ///
  /// In ja, this message translates to:
  /// **'確認しました'**
  String get apiConfirmed;

  /// No description provided for @apiAmount.
  ///
  /// In ja, this message translates to:
  /// **'見積金額（JPY）'**
  String get apiAmount;

  /// No description provided for @apiDueAt.
  ///
  /// In ja, this message translates to:
  /// **'期限（JST）'**
  String get apiDueAt;

  /// No description provided for @apiMessages.
  ///
  /// In ja, this message translates to:
  /// **'メッセージ'**
  String get apiMessages;

  /// No description provided for @apiMessageInput.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを入力'**
  String get apiMessageInput;

  /// No description provided for @apiSend.
  ///
  /// In ja, this message translates to:
  /// **'送信'**
  String get apiSend;

  /// No description provided for @apiMessageSent.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを送信しました'**
  String get apiMessageSent;

  /// No description provided for @apiReply.
  ///
  /// In ja, this message translates to:
  /// **'追加情報を送る'**
  String get apiReply;

  /// No description provided for @apiConsult.
  ///
  /// In ja, this message translates to:
  /// **'運営に問い合わせ'**
  String get apiConsult;

  /// No description provided for @apiConsultNotice.
  ///
  /// In ja, this message translates to:
  /// **'問い合わせでは案件の受注や協業は確定しません。合意済みの関係を運営が記録します。'**
  String get apiConsultNotice;

  /// No description provided for @apiDelivery.
  ///
  /// In ja, this message translates to:
  /// **'納品成果'**
  String get apiDelivery;

  /// No description provided for @apiOpenDelivery.
  ///
  /// In ja, this message translates to:
  /// **'納品物を提出'**
  String get apiOpenDelivery;

  /// No description provided for @providerOverview.
  ///
  /// In ja, this message translates to:
  /// **'担当プロジェクトの概要'**
  String get providerOverview;

  /// No description provided for @providerIntro.
  ///
  /// In ja, this message translates to:
  /// **'相談・開発・納品の状況を確認し、案件一覧から公開中の案件を探せます。'**
  String get providerIntro;

  /// No description provided for @providerCommunicating.
  ///
  /// In ja, this message translates to:
  /// **'相談中'**
  String get providerCommunicating;

  /// No description provided for @providerDelivered.
  ///
  /// In ja, this message translates to:
  /// **'提出済み'**
  String get providerDelivered;

  /// No description provided for @providerDeliveredHelp.
  ///
  /// In ja, this message translates to:
  /// **'提出済みには内部確認中・検収待ち・完了の案件が含まれます。各案件の状態をご確認ください。'**
  String get providerDeliveredHelp;

  /// No description provided for @providerHall.
  ///
  /// In ja, this message translates to:
  /// **'案件一覧'**
  String get providerHall;

  /// No description provided for @providerHallHelp.
  ///
  /// In ja, this message translates to:
  /// **'審査済みで公開中、かつ協業がまだ開始されていない案件を表示します。'**
  String get providerHallHelp;

  /// No description provided for @providerViewAll.
  ///
  /// In ja, this message translates to:
  /// **'すべて見る'**
  String get providerViewAll;

  /// No description provided for @negotiationTitle.
  ///
  /// In ja, this message translates to:
  /// **'協業相談と条件'**
  String get negotiationTitle;

  /// No description provided for @negotiationStart.
  ///
  /// In ja, this message translates to:
  /// **'案件について相談'**
  String get negotiationStart;

  /// No description provided for @negotiationProvider.
  ///
  /// In ja, this message translates to:
  /// **'担当者'**
  String get negotiationProvider;

  /// No description provided for @negotiationPropose.
  ///
  /// In ja, this message translates to:
  /// **'条件を提出してお客様に確認を依頼'**
  String get negotiationPropose;

  /// No description provided for @negotiationProposed.
  ///
  /// In ja, this message translates to:
  /// **'条件を提出しました。お客様の確認をお待ちください'**
  String get negotiationProposed;

  /// No description provided for @negotiationApprove.
  ///
  /// In ja, this message translates to:
  /// **'今回の範囲と条件を確認'**
  String get negotiationApprove;

  /// No description provided for @negotiationApproveBody.
  ///
  /// In ja, this message translates to:
  /// **'今回の公開範囲、担当者、条件、金額、期限を確認し、この条件での受注に同意します。確認後、担当者が受注することで開始します。支払いは発生しません。'**
  String get negotiationApproveBody;

  /// No description provided for @negotiationApproved.
  ///
  /// In ja, this message translates to:
  /// **'お客様が範囲と条件を確認しました。担当者の受注待ちです'**
  String get negotiationApproved;

  /// No description provided for @negotiationAwaiting.
  ///
  /// In ja, this message translates to:
  /// **'お客様による今回の範囲と条件の確認待ちです'**
  String get negotiationAwaiting;

  /// No description provided for @negotiationClaim.
  ///
  /// In ja, this message translates to:
  /// **'案件を受注'**
  String get negotiationClaim;

  /// No description provided for @negotiationClaimBody.
  ///
  /// In ja, this message translates to:
  /// **'お客様が確認した現在の範囲と条件で受注します。案件は現在のアカウントに割り当てられ、進行中になります。'**
  String get negotiationClaimBody;

  /// No description provided for @negotiationClaimed.
  ///
  /// In ja, this message translates to:
  /// **'受注しました。案件はご自身の担当となり、開始されました'**
  String get negotiationClaimed;

  /// No description provided for @negotiationEdit.
  ///
  /// In ja, this message translates to:
  /// **'条件を変更して再確認を依頼'**
  String get negotiationEdit;

  /// No description provided for @negotiationUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'この案件は公開終了または協業開始済みのため受注できません。'**
  String get negotiationUnavailable;

  /// No description provided for @negotiationOutdated.
  ///
  /// In ja, this message translates to:
  /// **'公開範囲が変更されました。現在の条件を再提出し、お客様に確認を依頼してください。'**
  String get negotiationOutdated;

  /// No description provided for @negotiationOptionalAmount.
  ///
  /// In ja, this message translates to:
  /// **'合意金額（JPY、任意）'**
  String get negotiationOptionalAmount;

  /// No description provided for @negotiationOptionalDue.
  ///
  /// In ja, this message translates to:
  /// **'期限を選択（JST 18:00、任意）'**
  String get negotiationOptionalDue;

  /// No description provided for @negotiationFormError.
  ///
  /// In ja, this message translates to:
  /// **'条件を入力してください。金額は有効な非負の整数で入力してください。'**
  String get negotiationFormError;

  /// No description provided for @apiSubmitDelivery.
  ///
  /// In ja, this message translates to:
  /// **'納品を確認に提出'**
  String get apiSubmitDelivery;

  /// No description provided for @apiSourceRepo.
  ///
  /// In ja, this message translates to:
  /// **'ソースリポジトリの HTTPS URL'**
  String get apiSourceRepo;

  /// No description provided for @apiSourceCommit.
  ///
  /// In ja, this message translates to:
  /// **'固定バージョン（40 または 64 桁 commit SHA）'**
  String get apiSourceCommit;

  /// No description provided for @apiSourceFile.
  ///
  /// In ja, this message translates to:
  /// **'ソースアーカイブ'**
  String get apiSourceFile;

  /// No description provided for @apiSourceArchiveRef.
  ///
  /// In ja, this message translates to:
  /// **'お客様がソースを取得できるアーカイブの証跡'**
  String get apiSourceArchiveRef;

  /// No description provided for @apiSourceHelp.
  ///
  /// In ja, this message translates to:
  /// **'HTTPS リポジトリ URL、完全な commit SHA、お客様が取得できるアーカイブの証跡を入力するか、安全確認済みのソースアーカイブを選択してください。'**
  String get apiSourceHelp;

  /// No description provided for @apiGuide.
  ///
  /// In ja, this message translates to:
  /// **'操作・デプロイ手順'**
  String get apiGuide;

  /// No description provided for @apiTestEvidence.
  ///
  /// In ja, this message translates to:
  /// **'実施したテストのコマンドと結果'**
  String get apiTestEvidence;

  /// No description provided for @apiDeliveryNote.
  ///
  /// In ja, this message translates to:
  /// **'納品の説明'**
  String get apiDeliveryNote;

  /// No description provided for @apiDeliverySubmitted.
  ///
  /// In ja, this message translates to:
  /// **'納品を保存しました。運営の確認後にお客様へ公開されます'**
  String get apiDeliverySubmitted;

  /// No description provided for @apiAccept.
  ///
  /// In ja, this message translates to:
  /// **'検収を確定'**
  String get apiAccept;

  /// No description provided for @apiAcceptBody.
  ///
  /// In ja, this message translates to:
  /// **'現在の納品バージョン、ソース、操作手順を確認し、合意範囲を満たすことを検証しました。検収を記録します。支払は行いません。'**
  String get apiAcceptBody;

  /// No description provided for @apiRevision.
  ///
  /// In ja, this message translates to:
  /// **'修正を依頼'**
  String get apiRevision;

  /// No description provided for @apiRevisionReason.
  ///
  /// In ja, this message translates to:
  /// **'問題と修正内容'**
  String get apiRevisionReason;

  /// No description provided for @apiChanged.
  ///
  /// In ja, this message translates to:
  /// **'状態を更新しました'**
  String get apiChanged;

  /// No description provided for @apiUnpublishedDelivery.
  ///
  /// In ja, this message translates to:
  /// **'運営の確認待ち'**
  String get apiUnpublishedDelivery;

  /// No description provided for @apiPublishedDelivery.
  ///
  /// In ja, this message translates to:
  /// **'お客様へ公開済み'**
  String get apiPublishedDelivery;

  /// No description provided for @apiNotifications.
  ///
  /// In ja, this message translates to:
  /// **'通知'**
  String get apiNotifications;

  /// No description provided for @apiMarkRead.
  ///
  /// In ja, this message translates to:
  /// **'既読にする'**
  String get apiMarkRead;

  /// No description provided for @apiNoNotifications.
  ///
  /// In ja, this message translates to:
  /// **'通知はありません'**
  String get apiNoNotifications;

  /// No description provided for @apiProfile.
  ///
  /// In ja, this message translates to:
  /// **'アカウント'**
  String get apiProfile;

  /// No description provided for @apiLogout.
  ///
  /// In ja, this message translates to:
  /// **'ログアウト'**
  String get apiLogout;

  /// No description provided for @apiSessionNotice.
  ///
  /// In ja, this message translates to:
  /// **'アプリを再起動した場合はログインしてください。言語設定は端末に、業務記録はサーバーに保存されます。'**
  String get apiSessionNotice;

  /// No description provided for @apiPasswordHelp.
  ///
  /// In ja, this message translates to:
  /// **'パスワード再設定メールは未対応です。運営にお問い合わせください。'**
  String get apiPasswordHelp;

  /// No description provided for @apiPasswordLength.
  ///
  /// In ja, this message translates to:
  /// **'登録パスワードは 12 文字以上'**
  String get apiPasswordLength;

  /// No description provided for @apiFilePreview.
  ///
  /// In ja, this message translates to:
  /// **'ファイルのプレビュー'**
  String get apiFilePreview;

  /// No description provided for @apiOfficeUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'Office/PDF のオンライン変換は未対応です。原本をダウンロードし、端末のアプリで開けます。'**
  String get apiOfficeUnavailable;

  /// No description provided for @apiDownload.
  ///
  /// In ja, this message translates to:
  /// **'原本をダウンロード'**
  String get apiDownload;

  /// No description provided for @apiOpenFile.
  ///
  /// In ja, this message translates to:
  /// **'ファイルを開く'**
  String get apiOpenFile;

  /// No description provided for @apiExportFile.
  ///
  /// In ja, this message translates to:
  /// **'ファイルアプリに保存'**
  String get apiExportFile;

  /// No description provided for @apiDownloadDone.
  ///
  /// In ja, this message translates to:
  /// **'アプリに原本を保存しました'**
  String get apiDownloadDone;

  /// No description provided for @apiExportDone.
  ///
  /// In ja, this message translates to:
  /// **'ファイルを保存しました'**
  String get apiExportDone;

  /// No description provided for @apiFileActionFailed.
  ///
  /// In ja, this message translates to:
  /// **'開く・保存操作が完了していません。再試行するか別のアプリを選択してください。'**
  String get apiFileActionFailed;

  /// No description provided for @apiRetry.
  ///
  /// In ja, this message translates to:
  /// **'再試行'**
  String get apiRetry;

  /// No description provided for @apiCancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get apiCancel;

  /// No description provided for @apiLoading.
  ///
  /// In ja, this message translates to:
  /// **'読み込み中…'**
  String get apiLoading;

  /// No description provided for @apiNetworkError.
  ///
  /// In ja, this message translates to:
  /// **'サーバーに接続できません。接続を確認して再試行してください。'**
  String get apiNetworkError;

  /// No description provided for @apiConflict.
  ///
  /// In ja, this message translates to:
  /// **'記録が更新されています。更新して最新バージョンを確認してから提出してください。'**
  String get apiConflict;

  /// No description provided for @apiForbidden.
  ///
  /// In ja, this message translates to:
  /// **'この操作を行う権限がありません。更新または再ログインしてください。'**
  String get apiForbidden;

  /// No description provided for @apiUnexpected.
  ///
  /// In ja, this message translates to:
  /// **'サービスを利用できません。しばらくしてから再試行してください。'**
  String get apiUnexpected;

  /// No description provided for @apiApiSetup.
  ///
  /// In ja, this message translates to:
  /// **'サービス URL が未設定です。OPC_API_BASE_URL に HTTPS API を設定してください。ローカルデバッグのみループバック HTTP を許可します。'**
  String get apiApiSetup;

  /// No description provided for @apiDraft.
  ///
  /// In ja, this message translates to:
  /// **'下書き'**
  String get apiDraft;

  /// No description provided for @apiPlay.
  ///
  /// In ja, this message translates to:
  /// **'再生 / 一時停止'**
  String get apiPlay;

  /// No description provided for @apiNoPreview.
  ///
  /// In ja, this message translates to:
  /// **'この形式はアプリ内プレビュー未対応です。原本をダウンロードして開いてください。'**
  String get apiNoPreview;

  /// No description provided for @apiSafetyNotice.
  ///
  /// In ja, this message translates to:
  /// **'アップロード後は運営の安全確認をお待ちください。完了後に更新して提出してください。確認前のファイルは正式な添付として提出できません。'**
  String get apiSafetyNotice;

  /// No description provided for @apiScopeIncluded.
  ///
  /// In ja, this message translates to:
  /// **'対象範囲'**
  String get apiScopeIncluded;

  /// No description provided for @apiScopeExcluded.
  ///
  /// In ja, this message translates to:
  /// **'対象外の範囲'**
  String get apiScopeExcluded;

  /// No description provided for @apiScopeDeliverables.
  ///
  /// In ja, this message translates to:
  /// **'合意した成果物'**
  String get apiScopeDeliverables;

  /// No description provided for @apiScopeAcceptance.
  ///
  /// In ja, this message translates to:
  /// **'検収基準'**
  String get apiScopeAcceptance;

  /// No description provided for @apiScopeRevision.
  ///
  /// In ja, this message translates to:
  /// **'修正条件'**
  String get apiScopeRevision;

  /// No description provided for @apiWithdrawn.
  ///
  /// In ja, this message translates to:
  /// **'取り下げ済み'**
  String get apiWithdrawn;

  /// No description provided for @apiRejected.
  ///
  /// In ja, this message translates to:
  /// **'審査で却下'**
  String get apiRejected;

  /// No description provided for @apiCancelled.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル済み'**
  String get apiCancelled;

  /// No description provided for @apiTextTruncated.
  ///
  /// In ja, this message translates to:
  /// **'原文の一部のみ表示しています。全文は原本をダウンロードして確認してください。'**
  String get apiTextTruncated;

  /// No description provided for @apiRequestUpdated.
  ///
  /// In ja, this message translates to:
  /// **'相談が更新されました'**
  String get apiRequestUpdated;

  /// No description provided for @apiTermsUpdated.
  ///
  /// In ja, this message translates to:
  /// **'協業条件が更新されました。再確認してください'**
  String get apiTermsUpdated;

  /// No description provided for @apiDeliveryReviewed.
  ///
  /// In ja, this message translates to:
  /// **'納品の内部確認が完了しました'**
  String get apiDeliveryReviewed;

  /// No description provided for @apiDeliveryWithdrawn.
  ///
  /// In ja, this message translates to:
  /// **'納品が取り下げられました。更新をお待ちください'**
  String get apiDeliveryWithdrawn;

  /// No description provided for @apiPublicationWithdrawn.
  ///
  /// In ja, this message translates to:
  /// **'案件が一覧から取り下げられました'**
  String get apiPublicationWithdrawn;

  /// No description provided for @apiFileUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'ファイルにアクセスできないか、安全確認が未完了です。状態を更新してください。'**
  String get apiFileUnavailable;

  /// No description provided for @classificationPlatform.
  ///
  /// In ja, this message translates to:
  /// **'開発対象'**
  String get classificationPlatform;

  /// No description provided for @classificationType.
  ///
  /// In ja, this message translates to:
  /// **'開発システム種別'**
  String get classificationType;

  /// No description provided for @classificationAll.
  ///
  /// In ja, this message translates to:
  /// **'すべて'**
  String get classificationAll;

  /// No description provided for @classificationUnclassified.
  ///
  /// In ja, this message translates to:
  /// **'未分類'**
  String get classificationUnclassified;

  /// No description provided for @classificationClear.
  ///
  /// In ja, this message translates to:
  /// **'分類の絞り込みを解除'**
  String get classificationClear;

  /// No description provided for @classificationOptional.
  ///
  /// In ja, this message translates to:
  /// **'任意：主な開発対象とシステム種別を選択できます。未選択の場合は未分類です。'**
  String get classificationOptional;

  /// No description provided for @authDemoAccounts.
  ///
  /// In ja, this message translates to:
  /// **'デモアカウント'**
  String get authDemoAccounts;

  /// No description provided for @authDemoInfo.
  ///
  /// In ja, this message translates to:
  /// **'データはこのアプリ内のサンプルです。実際の登録・送信・アップロードは行いません。再起動でデータはリセットされますが、言語設定は保存されます。'**
  String get authDemoInfo;

  /// No description provided for @authTryCustomer.
  ///
  /// In ja, this message translates to:
  /// **'お客様として試す'**
  String get authTryCustomer;

  /// No description provided for @authTryMember.
  ///
  /// In ja, this message translates to:
  /// **'内部メンバーとして試す'**
  String get authTryMember;

  /// No description provided for @authResetTitle.
  ///
  /// In ja, this message translates to:
  /// **'パスワードの再設定'**
  String get authResetTitle;

  /// No description provided for @authResetHelp.
  ///
  /// In ja, this message translates to:
  /// **'デモ環境ではメールを送信しません。デモアカウントのパスワードは demo1234 です。\n\n新しく登録したアカウントはアプリの再起動またはデモのリセットで削除されます。'**
  String get authResetHelp;

  /// No description provided for @authTheme.
  ///
  /// In ja, this message translates to:
  /// **'テーマを切り替える'**
  String get authTheme;

  /// No description provided for @authEyebrow.
  ///
  /// In ja, this message translates to:
  /// **'AI DEVELOPMENT, TOGETHER'**
  String get authEyebrow;

  /// No description provided for @authRegisterHero.
  ///
  /// In ja, this message translates to:
  /// **'アイデアを、\nここから一緒に。'**
  String get authRegisterHero;

  /// No description provided for @authLoginHero.
  ///
  /// In ja, this message translates to:
  /// **'つくりたいを、\n動くかたちに。'**
  String get authLoginHero;

  /// No description provided for @authIntro.
  ///
  /// In ja, this message translates to:
  /// **'アイデアの相談から、開発・納品まで。\nあなたの一歩を、OPC がサポートします。'**
  String get authIntro;

  /// No description provided for @authNoExpertise.
  ///
  /// In ja, this message translates to:
  /// **'専門知識はなくても大丈夫'**
  String get authNoExpertise;

  /// No description provided for @authReviewHelp.
  ///
  /// In ja, this message translates to:
  /// **'運営がご依頼を確認し、要件を整理します。'**
  String get authReviewHelp;

  /// No description provided for @authName.
  ///
  /// In ja, this message translates to:
  /// **'お名前'**
  String get authName;

  /// No description provided for @authNameHint.
  ///
  /// In ja, this message translates to:
  /// **'お名前を入力'**
  String get authNameHint;

  /// No description provided for @authNameRequired.
  ///
  /// In ja, this message translates to:
  /// **'お名前を入力してください'**
  String get authNameRequired;

  /// No description provided for @authEmail.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレス'**
  String get authEmail;

  /// No description provided for @authEmailInvalid.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレスを確認してください'**
  String get authEmailInvalid;

  /// No description provided for @authPassword.
  ///
  /// In ja, this message translates to:
  /// **'パスワード'**
  String get authPassword;

  /// No description provided for @authPasswordNewHint.
  ///
  /// In ja, this message translates to:
  /// **'8文字以上で入力'**
  String get authPasswordNewHint;

  /// No description provided for @authPasswordHint.
  ///
  /// In ja, this message translates to:
  /// **'パスワードを入力'**
  String get authPasswordHint;

  /// No description provided for @authShowPassword.
  ///
  /// In ja, this message translates to:
  /// **'パスワードを表示'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In ja, this message translates to:
  /// **'パスワードを隠す'**
  String get authHidePassword;

  /// No description provided for @authPasswordRequired.
  ///
  /// In ja, this message translates to:
  /// **'パスワードを入力してください（登録時は8文字以上）'**
  String get authPasswordRequired;

  /// No description provided for @authForgot.
  ///
  /// In ja, this message translates to:
  /// **'パスワードをお忘れですか？'**
  String get authForgot;

  /// No description provided for @authBusy.
  ///
  /// In ja, this message translates to:
  /// **'確認しています…'**
  String get authBusy;

  /// No description provided for @authRegisterSubmit.
  ///
  /// In ja, this message translates to:
  /// **'登録して相談をはじめる'**
  String get authRegisterSubmit;

  /// No description provided for @authLogin.
  ///
  /// In ja, this message translates to:
  /// **'ログインする'**
  String get authLogin;

  /// No description provided for @authExisting.
  ///
  /// In ja, this message translates to:
  /// **'アカウントをお持ちの方'**
  String get authExisting;

  /// No description provided for @authNew.
  ///
  /// In ja, this message translates to:
  /// **'はじめてご利用の方'**
  String get authNew;

  /// No description provided for @authBackLogin.
  ///
  /// In ja, this message translates to:
  /// **'ログインに戻る'**
  String get authBackLogin;

  /// No description provided for @authRegister.
  ///
  /// In ja, this message translates to:
  /// **'新規登録して相談する'**
  String get authRegister;

  /// No description provided for @authInternalLogin.
  ///
  /// In ja, this message translates to:
  /// **'内部アカウントをお持ちの方も、こちらからログイン'**
  String get authInternalLogin;

  /// No description provided for @authLegalTitle.
  ///
  /// In ja, this message translates to:
  /// **'利用規約・プライバシー'**
  String get authLegalTitle;

  /// No description provided for @authLegalHelp.
  ///
  /// In ja, this message translates to:
  /// **'現在は合成データによる デモです。正式な利用規約・個人情報の取扱いは本番提供前に設定します。実際の個人情報や秘密情報を入力しないでください。'**
  String get authLegalHelp;

  /// No description provided for @hallTitle.
  ///
  /// In ja, this message translates to:
  /// **'案件一覧'**
  String get hallTitle;

  /// No description provided for @hallSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'あなたの技術を、次のプロジェクトへ'**
  String get hallSubtitle;

  /// No description provided for @hallNotifications.
  ///
  /// In ja, this message translates to:
  /// **'お知らせ'**
  String get hallNotifications;

  /// No description provided for @hallInternal.
  ///
  /// In ja, this message translates to:
  /// **'内部アカウント'**
  String get hallInternal;

  /// No description provided for @hallPublishedWork.
  ///
  /// In ja, this message translates to:
  /// **'公開済みの開発案件'**
  String get hallPublishedWork;

  /// No description provided for @hallSearch.
  ///
  /// In ja, this message translates to:
  /// **'キーワードで案件を探す'**
  String get hallSearch;

  /// No description provided for @hallSort.
  ///
  /// In ja, this message translates to:
  /// **'更新が新しい順'**
  String get hallSort;

  /// No description provided for @hallEmpty.
  ///
  /// In ja, this message translates to:
  /// **'該当する案件はありません'**
  String get hallEmpty;

  /// No description provided for @hallEmptyHelp.
  ///
  /// In ja, this message translates to:
  /// **'キーワードや条件を変えてお試しください。'**
  String get hallEmptyHelp;

  /// No description provided for @hallPublished.
  ///
  /// In ja, this message translates to:
  /// **'公開中'**
  String get hallPublished;

  /// No description provided for @hallStructured.
  ///
  /// In ja, this message translates to:
  /// **'要件整理済み'**
  String get hallStructured;

  /// No description provided for @hallView.
  ///
  /// In ja, this message translates to:
  /// **'詳細を見る'**
  String get hallView;

  /// No description provided for @hallDetail.
  ///
  /// In ja, this message translates to:
  /// **'案件詳細'**
  String get hallDetail;

  /// No description provided for @hallDevelopment.
  ///
  /// In ja, this message translates to:
  /// **'開発サービス'**
  String get hallDevelopment;

  /// No description provided for @hallConsult.
  ///
  /// In ja, this message translates to:
  /// **'案件について相談する'**
  String get hallConsult;

  /// No description provided for @hallNotAssigned.
  ///
  /// In ja, this message translates to:
  /// **'相談の送信だけでは、担当は確定しません。'**
  String get hallNotAssigned;

  /// No description provided for @hallDuration.
  ///
  /// In ja, this message translates to:
  /// **'開発期間の目安'**
  String get hallDuration;

  /// No description provided for @hallMethod.
  ///
  /// In ja, this message translates to:
  /// **'進め方'**
  String get hallMethod;

  /// No description provided for @hallOnline.
  ///
  /// In ja, this message translates to:
  /// **'オンライン'**
  String get hallOnline;

  /// No description provided for @hallScope.
  ///
  /// In ja, this message translates to:
  /// **'今回つくるもの'**
  String get hallScope;

  /// No description provided for @hallScopeHelp.
  ///
  /// In ja, this message translates to:
  /// **'具体的な機能・対象範囲は、公開された説明をもとに運営と確認します。'**
  String get hallScopeHelp;

  /// No description provided for @hallDeliverables.
  ///
  /// In ja, this message translates to:
  /// **'交付物と確認ポイント'**
  String get hallDeliverables;

  /// No description provided for @hallFiles.
  ///
  /// In ja, this message translates to:
  /// **'ソースコード / 操作説明書 / テスト結果'**
  String get hallFiles;

  /// No description provided for @hallIndividualScope.
  ///
  /// In ja, this message translates to:
  /// **'納品物の内容・確認ポイントは、運営が整理した範囲に沿って個別に確認します。'**
  String get hallIndividualScope;

  /// No description provided for @hallPrivateHelp.
  ///
  /// In ja, this message translates to:
  /// **'詳細な資料と担当範囲は、運営との相談時に確認します。非公開の添付資料は案件一覧に表示されません。'**
  String get hallPrivateHelp;

  /// No description provided for @hallConsultHelp.
  ///
  /// In ja, this message translates to:
  /// **'確認したいことや対応できる範囲をお伝えください。担当の確定方法は運営が別途ご案内します。'**
  String get hallConsultHelp;

  /// No description provided for @hallConsultHint.
  ///
  /// In ja, this message translates to:
  /// **'相談内容を入力'**
  String get hallConsultHint;

  /// No description provided for @hallConsultRequired.
  ///
  /// In ja, this message translates to:
  /// **'相談内容を入力してください'**
  String get hallConsultRequired;

  /// No description provided for @hallSending.
  ///
  /// In ja, this message translates to:
  /// **'送信中…'**
  String get hallSending;

  /// No description provided for @hallSend.
  ///
  /// In ja, this message translates to:
  /// **'相談を送信する'**
  String get hallSend;

  /// No description provided for @hallSent.
  ///
  /// In ja, this message translates to:
  /// **'相談を送信しました。担当はまだ確定していません。'**
  String get hallSent;

  /// No description provided for @coreBack.
  ///
  /// In ja, this message translates to:
  /// **'戻る'**
  String get coreBack;

  /// No description provided for @coreBackLogin.
  ///
  /// In ja, this message translates to:
  /// **'ログイン画面へ戻る'**
  String get coreBackLogin;

  /// No description provided for @coreActionFailed.
  ///
  /// In ja, this message translates to:
  /// **'処理できませんでした。もう一度お試しください。'**
  String get coreActionFailed;

  /// No description provided for @coreNeedsInfo.
  ///
  /// In ja, this message translates to:
  /// **'回答が必要'**
  String get coreNeedsInfo;

  /// No description provided for @coreReviewing.
  ///
  /// In ja, this message translates to:
  /// **'内容を確認中'**
  String get coreReviewing;

  /// No description provided for @corePublished.
  ///
  /// In ja, this message translates to:
  /// **'公開中'**
  String get corePublished;

  /// No description provided for @coreDeveloping.
  ///
  /// In ja, this message translates to:
  /// **'開発中'**
  String get coreDeveloping;

  /// No description provided for @coreInternalReview.
  ///
  /// In ja, this message translates to:
  /// **'運営が確認中'**
  String get coreInternalReview;

  /// No description provided for @coreAwaitingAcceptance.
  ///
  /// In ja, this message translates to:
  /// **'ご確認待ち'**
  String get coreAwaitingAcceptance;

  /// No description provided for @coreRevision.
  ///
  /// In ja, this message translates to:
  /// **'修正対応中'**
  String get coreRevision;

  /// No description provided for @coreCompleted.
  ///
  /// In ja, this message translates to:
  /// **'検収完了'**
  String get coreCompleted;

  /// No description provided for @coreClose.
  ///
  /// In ja, this message translates to:
  /// **'閉じる'**
  String get coreClose;

  /// No description provided for @coreLanguage.
  ///
  /// In ja, this message translates to:
  /// **'表示言語'**
  String get coreLanguage;

  /// No description provided for @coreJapanese.
  ///
  /// In ja, this message translates to:
  /// **'日本語'**
  String get coreJapanese;

  /// No description provided for @coreChinese.
  ///
  /// In ja, this message translates to:
  /// **'简体中文'**
  String get coreChinese;

  /// No description provided for @coreLanguageSaveFailed.
  ///
  /// In ja, this message translates to:
  /// **'言語設定を保存できませんでした。再起動後は元の言語に戻る場合があります。'**
  String get coreLanguageSaveFailed;

  /// No description provided for @coreSetup.
  ///
  /// In ja, this message translates to:
  /// **'接続設定が必要です。現在のバージョンはデモ専用です。'**
  String get coreSetup;

  /// No description provided for @coreAll.
  ///
  /// In ja, this message translates to:
  /// **'すべて'**
  String get coreAll;

  /// No description provided for @coreWeb.
  ///
  /// In ja, this message translates to:
  /// **'Web アプリ'**
  String get coreWeb;

  /// No description provided for @coreAutomation.
  ///
  /// In ja, this message translates to:
  /// **'業務自動化'**
  String get coreAutomation;

  /// No description provided for @coreAi.
  ///
  /// In ja, this message translates to:
  /// **'AI 開発'**
  String get coreAi;

  /// No description provided for @errorSessionChanged.
  ///
  /// In ja, this message translates to:
  /// **'アカウントの状態が変わりました。画面を開き直してください。'**
  String get errorSessionChanged;

  /// No description provided for @errorNetwork.
  ///
  /// In ja, this message translates to:
  /// **'デモ通信に失敗しました。内容を確認して、もう一度お試しください。'**
  String get errorNetwork;

  /// No description provided for @errorUnauthenticated.
  ///
  /// In ja, this message translates to:
  /// **'ログインしてください。'**
  String get errorUnauthenticated;

  /// No description provided for @errorInactive.
  ///
  /// In ja, this message translates to:
  /// **'このアカウントは停止中です。'**
  String get errorInactive;

  /// No description provided for @errorCustomer.
  ///
  /// In ja, this message translates to:
  /// **'お客様のアカウントでご利用ください。'**
  String get errorCustomer;

  /// No description provided for @errorProvider.
  ///
  /// In ja, this message translates to:
  /// **'有効な内部承接権限が必要です。'**
  String get errorProvider;

  /// No description provided for @errorNotFound.
  ///
  /// In ja, this message translates to:
  /// **'この案件を表示できません。'**
  String get errorNotFound;

  /// No description provided for @errorCredentials.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレスまたはパスワードをご確認ください。'**
  String get errorCredentials;

  /// No description provided for @errorName.
  ///
  /// In ja, this message translates to:
  /// **'お名前を80文字以内で入力してください。'**
  String get errorName;

  /// No description provided for @errorEmail.
  ///
  /// In ja, this message translates to:
  /// **'有効なメールアドレスを入力してください。'**
  String get errorEmail;

  /// No description provided for @errorPassword.
  ///
  /// In ja, this message translates to:
  /// **'パスワードは8文字以上で入力してください。'**
  String get errorPassword;

  /// No description provided for @errorEmailExists.
  ///
  /// In ja, this message translates to:
  /// **'このメールアドレスは登録済みです。'**
  String get errorEmailExists;

  /// No description provided for @errorDescription.
  ///
  /// In ja, this message translates to:
  /// **'ご相談内容を10〜4,000文字で入力してください。'**
  String get errorDescription;

  /// No description provided for @errorRequest.
  ///
  /// In ja, this message translates to:
  /// **'希望時期とご予算の意向を選んでください。'**
  String get errorRequest;

  /// No description provided for @errorAttachments.
  ///
  /// In ja, this message translates to:
  /// **'添付資料は5件以内で指定してください。'**
  String get errorAttachments;

  /// No description provided for @errorMessage.
  ///
  /// In ja, this message translates to:
  /// **'内容を1〜4,000文字で入力してください。'**
  String get errorMessage;

  /// No description provided for @errorState.
  ///
  /// In ja, this message translates to:
  /// **'案件の状態が変わりました。最新の状態を確認してください。'**
  String get errorState;

  /// No description provided for @errorVersion.
  ///
  /// In ja, this message translates to:
  /// **'公開中の最新納品バージョンを確認してください。'**
  String get errorVersion;

  /// No description provided for @errorDelivery.
  ///
  /// In ja, this message translates to:
  /// **'固定ソース・操作説明・テスト資料・提出コメントを入力してください。'**
  String get errorDelivery;

  /// No description provided for @errorSource.
  ///
  /// In ja, this message translates to:
  /// **'ソースの固定バージョンまたはチェックサムを指定してください。'**
  String get errorSource;

  /// No description provided for @hallCount.
  ///
  /// In ja, this message translates to:
  /// **'開発案件 {count}件'**
  String hallCount(int count);

  /// No description provided for @hallEstimate.
  ///
  /// In ja, this message translates to:
  /// **'目安：{duration}'**
  String hallEstimate(String duration);

  /// No description provided for @hallVersion.
  ///
  /// In ja, this message translates to:
  /// **'整理済み要件 v{version}.0'**
  String hallVersion(int version);

  /// No description provided for @customerRequestsTitle.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼一覧'**
  String get customerRequestsTitle;

  /// No description provided for @customerWorkspaceSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'お客様向けワークスペース'**
  String get customerWorkspaceSubtitle;

  /// No description provided for @customerNotifications.
  ///
  /// In ja, this message translates to:
  /// **'お知らせ'**
  String get customerNotifications;

  /// No description provided for @customerHeroTitle.
  ///
  /// In ja, this message translates to:
  /// **'つくりたいこと、\n相談してみませんか。'**
  String get customerHeroTitle;

  /// No description provided for @customerHeroSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'専門用語は不要です。運営が一緒に整理します。'**
  String get customerHeroSubtitle;

  /// No description provided for @customerCreateRequest.
  ///
  /// In ja, this message translates to:
  /// **'開発を相談する'**
  String get customerCreateRequest;

  /// No description provided for @customerContinueDraft.
  ///
  /// In ja, this message translates to:
  /// **'保存した下書きを続ける'**
  String get customerContinueDraft;

  /// No description provided for @customerActiveRequests.
  ///
  /// In ja, this message translates to:
  /// **'進行中のご依頼'**
  String get customerActiveRequests;

  /// No description provided for @customerNoRequests.
  ///
  /// In ja, this message translates to:
  /// **'まだご依頼はありません'**
  String get customerNoRequests;

  /// No description provided for @customerNoRequestsHint.
  ///
  /// In ja, this message translates to:
  /// **'「開発を相談する」から、アイデアをお聞かせください。'**
  String get customerNoRequestsHint;

  /// No description provided for @customerProgressHint.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼の進捗をご確認いただけます'**
  String get customerProgressHint;

  /// No description provided for @customerDraftSaved.
  ///
  /// In ja, this message translates to:
  /// **'このデモの下書きに保存しました'**
  String get customerDraftSaved;

  /// No description provided for @customerAddReference.
  ///
  /// In ja, this message translates to:
  /// **'参考資料を追加'**
  String get customerAddReference;

  /// No description provided for @customerAttachmentNote.
  ///
  /// In ja, this message translates to:
  /// **'サンプル名を選択します。端末のファイル選択・アップロードは行いません。'**
  String get customerAttachmentNote;

  /// No description provided for @customerAssistTitle.
  ///
  /// In ja, this message translates to:
  /// **'相談内容の整理案'**
  String get customerAssistTitle;

  /// No description provided for @customerAssistNote.
  ///
  /// In ja, this message translates to:
  /// **'端末内の定型ルールによる提案です。AI への送信・自動審査は行いません。'**
  String get customerAssistNote;

  /// No description provided for @customerKeepOriginal.
  ///
  /// In ja, this message translates to:
  /// **'元の内容を使う'**
  String get customerKeepOriginal;

  /// No description provided for @customerAdoptSuggestion.
  ///
  /// In ja, this message translates to:
  /// **'この案を採用'**
  String get customerAdoptSuggestion;

  /// No description provided for @customerConfirmTitle.
  ///
  /// In ja, this message translates to:
  /// **'ご相談内容の確認'**
  String get customerConfirmTitle;

  /// No description provided for @customerFormTitle.
  ///
  /// In ja, this message translates to:
  /// **'開発のご相談'**
  String get customerFormTitle;

  /// No description provided for @customerConfirmSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'送信前に内容をご確認ください'**
  String get customerConfirmSubtitle;

  /// No description provided for @customerFormSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'アイデアから、一緒にはじめましょう'**
  String get customerFormSubtitle;

  /// No description provided for @customerProcessing.
  ///
  /// In ja, this message translates to:
  /// **'処理中…'**
  String get customerProcessing;

  /// No description provided for @customerSubmitRequest.
  ///
  /// In ja, this message translates to:
  /// **'この内容で相談する'**
  String get customerSubmitRequest;

  /// No description provided for @customerProceedConfirmation.
  ///
  /// In ja, this message translates to:
  /// **'確認画面へ'**
  String get customerProceedConfirmation;

  /// No description provided for @customerEditRequest.
  ///
  /// In ja, this message translates to:
  /// **'内容を修正する'**
  String get customerEditRequest;

  /// No description provided for @customerSaveDraft.
  ///
  /// In ja, this message translates to:
  /// **'下書きとして保存'**
  String get customerSaveDraft;

  /// No description provided for @customerFormStep.
  ///
  /// In ja, this message translates to:
  /// **'1  ご相談内容'**
  String get customerFormStep;

  /// No description provided for @customerConfirmStep.
  ///
  /// In ja, this message translates to:
  /// **'2  内容の確認'**
  String get customerConfirmStep;

  /// No description provided for @customerServiceCategory.
  ///
  /// In ja, this message translates to:
  /// **'開発・AI 開発システム'**
  String get customerServiceCategory;

  /// No description provided for @customerGoalLabel.
  ///
  /// In ja, this message translates to:
  /// **'実現したいこと'**
  String get customerGoalLabel;

  /// No description provided for @customerTimingLabel.
  ///
  /// In ja, this message translates to:
  /// **'ご希望の時期'**
  String get customerTimingLabel;

  /// No description provided for @customerBudgetLabel.
  ///
  /// In ja, this message translates to:
  /// **'ご予算の目安'**
  String get customerBudgetLabel;

  /// No description provided for @customerReferenceLabel.
  ///
  /// In ja, this message translates to:
  /// **'参考資料'**
  String get customerReferenceLabel;

  /// No description provided for @customerNoAttachments.
  ///
  /// In ja, this message translates to:
  /// **'資料なし'**
  String get customerNoAttachments;

  /// No description provided for @customerConfirmNotice.
  ///
  /// In ja, this message translates to:
  /// **'運営が合規性と技術要件を確認・整理します。送信だけで案件一覧には公開されません。予算はご希望の目安であり、お支払いは発生しません。'**
  String get customerConfirmNotice;

  /// No description provided for @customerFormIntro.
  ///
  /// In ja, this message translates to:
  /// **'まだアイデア段階でも大丈夫です。\n実現したいことを、ご自身の言葉で教えてください。'**
  String get customerFormIntro;

  /// No description provided for @customerGoalQuestion.
  ///
  /// In ja, this message translates to:
  /// **'どんなことを実現したいですか？'**
  String get customerGoalQuestion;

  /// No description provided for @customerRequired.
  ///
  /// In ja, this message translates to:
  /// **'必須'**
  String get customerRequired;

  /// No description provided for @customerGoalHint.
  ///
  /// In ja, this message translates to:
  /// **'実現したいことを教えてください'**
  String get customerGoalHint;

  /// No description provided for @customerGoalValidation.
  ///
  /// In ja, this message translates to:
  /// **'実現したいことを10文字以上でご入力ください'**
  String get customerGoalValidation;

  /// No description provided for @customerAssistAction.
  ///
  /// In ja, this message translates to:
  /// **'AI で相談内容を整理する'**
  String get customerAssistAction;

  /// No description provided for @customerOptionalReference.
  ///
  /// In ja, this message translates to:
  /// **'参考資料（任意）'**
  String get customerOptionalReference;

  /// No description provided for @customerAddFiles.
  ///
  /// In ja, this message translates to:
  /// **'資料や画像を追加'**
  String get customerAddFiles;

  /// No description provided for @customerSampleReference.
  ///
  /// In ja, this message translates to:
  /// **'サンプル資料'**
  String get customerSampleReference;

  /// No description provided for @customerSubmitNotice.
  ///
  /// In ja, this message translates to:
  /// **'送信後、運営が内容を確認・整理します。\nこの時点では案件一覧に公開されません。'**
  String get customerSubmitNotice;

  /// No description provided for @customerReviewTitle.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼の確認状況'**
  String get customerReviewTitle;

  /// No description provided for @customerReviewSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'運営が内容を確認・整理しています'**
  String get customerReviewSubtitle;

  /// No description provided for @customerReplyAction.
  ///
  /// In ja, this message translates to:
  /// **'質問に回答する'**
  String get customerReplyAction;

  /// No description provided for @customerBackToRequests.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼一覧へ'**
  String get customerBackToRequests;

  /// No description provided for @customerPublished.
  ///
  /// In ja, this message translates to:
  /// **'公開済み'**
  String get customerPublished;

  /// No description provided for @customerUnderReview.
  ///
  /// In ja, this message translates to:
  /// **'内容を確認中'**
  String get customerUnderReview;

  /// No description provided for @customerReviewSteps.
  ///
  /// In ja, this message translates to:
  /// **'公開までのステップ'**
  String get customerReviewSteps;

  /// No description provided for @customerReceivedStep.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼を受付'**
  String get customerReceivedStep;

  /// No description provided for @customerReceivedStepDetail.
  ///
  /// In ja, this message translates to:
  /// **'内容を受け付けました'**
  String get customerReceivedStepDetail;

  /// No description provided for @customerComplianceStep.
  ///
  /// In ja, this message translates to:
  /// **'合規性の確認'**
  String get customerComplianceStep;

  /// No description provided for @customerComplianceComplete.
  ///
  /// In ja, this message translates to:
  /// **'運営による確認が完了しました'**
  String get customerComplianceComplete;

  /// No description provided for @customerCompliancePending.
  ///
  /// In ja, this message translates to:
  /// **'運営による確認をお待ちください'**
  String get customerCompliancePending;

  /// No description provided for @customerRequirementsStep.
  ///
  /// In ja, this message translates to:
  /// **'要件を整理'**
  String get customerRequirementsStep;

  /// No description provided for @customerRequirementsComplete.
  ///
  /// In ja, this message translates to:
  /// **'技術要件の整理が完了しました'**
  String get customerRequirementsComplete;

  /// No description provided for @customerRequirementsNeedsInfo.
  ///
  /// In ja, this message translates to:
  /// **'追加の情報をお待ちしています'**
  String get customerRequirementsNeedsInfo;

  /// No description provided for @customerRequirementsPending.
  ///
  /// In ja, this message translates to:
  /// **'運営が内容を確認・整理します'**
  String get customerRequirementsPending;

  /// No description provided for @customerPublicationStep.
  ///
  /// In ja, this message translates to:
  /// **'案件一覧に公開'**
  String get customerPublicationStep;

  /// No description provided for @customerPublicationComplete.
  ///
  /// In ja, this message translates to:
  /// **'確認済みのバージョンを公開しました'**
  String get customerPublicationComplete;

  /// No description provided for @customerPublicationPending.
  ///
  /// In ja, this message translates to:
  /// **'すべての確認が終わってから公開'**
  String get customerPublicationPending;

  /// No description provided for @customerOperatorQuestion.
  ///
  /// In ja, this message translates to:
  /// **'運営からの確認事項'**
  String get customerOperatorQuestion;

  /// No description provided for @customerOperatorAwaitingReply.
  ///
  /// In ja, this message translates to:
  /// **'OPC 運営 · 回答をお待ちしています'**
  String get customerOperatorAwaitingReply;

  /// No description provided for @customerOperatorReplyReceived.
  ///
  /// In ja, this message translates to:
  /// **'OPC 運営 · 回答を受け付けました'**
  String get customerOperatorReplyReceived;

  /// No description provided for @customerSupplementConversation.
  ///
  /// In ja, this message translates to:
  /// **'補足・やりとり'**
  String get customerSupplementConversation;

  /// No description provided for @customerPublicationNotice.
  ///
  /// In ja, this message translates to:
  /// **'審査を通過した公開バージョンのみ、案件一覧に表示されます。'**
  String get customerPublicationNotice;

  /// No description provided for @customerUnpublishedNotice.
  ///
  /// In ja, this message translates to:
  /// **'この依頼は、まだ案件一覧に公開されていません。'**
  String get customerUnpublishedNotice;

  /// No description provided for @customerReplySuccess.
  ///
  /// In ja, this message translates to:
  /// **'回答を送信しました。運営の確認をお待ちください。'**
  String get customerReplySuccess;

  /// No description provided for @customerReplyLabel.
  ///
  /// In ja, this message translates to:
  /// **'ご回答'**
  String get customerReplyLabel;

  /// No description provided for @customerReplyHint.
  ///
  /// In ja, this message translates to:
  /// **'例：利用者は30名ほど、参考資料はPDFです。'**
  String get customerReplyHint;

  /// No description provided for @customerReplyValidation.
  ///
  /// In ja, this message translates to:
  /// **'回答をご入力ください'**
  String get customerReplyValidation;

  /// No description provided for @customerReplyNotice.
  ///
  /// In ja, this message translates to:
  /// **'回答は運営が確認します。送信後も自動的には審査・公開されません。'**
  String get customerReplyNotice;

  /// No description provided for @customerSending.
  ///
  /// In ja, this message translates to:
  /// **'送信中…'**
  String get customerSending;

  /// No description provided for @customerSendReply.
  ///
  /// In ja, this message translates to:
  /// **'回答を送信'**
  String get customerSendReply;

  /// No description provided for @customerRequestDetail.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼の詳細'**
  String get customerRequestDetail;

  /// No description provided for @customerNoNotifications.
  ///
  /// In ja, this message translates to:
  /// **'新しいお知らせはありません。'**
  String get customerNoNotifications;

  /// No description provided for @customerWorkspace.
  ///
  /// In ja, this message translates to:
  /// **'ワークスペース'**
  String get customerWorkspace;

  /// No description provided for @customerTasks.
  ///
  /// In ja, this message translates to:
  /// **'案件'**
  String get customerTasks;

  /// No description provided for @customerHome.
  ///
  /// In ja, this message translates to:
  /// **'ホーム'**
  String get customerHome;

  /// No description provided for @customerProjects.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクト'**
  String get customerProjects;

  /// No description provided for @customerRequests.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼'**
  String get customerRequests;

  /// No description provided for @customerMessages.
  ///
  /// In ja, this message translates to:
  /// **'メッセージ'**
  String get customerMessages;

  /// No description provided for @customerProfile.
  ///
  /// In ja, this message translates to:
  /// **'マイページ'**
  String get customerProfile;

  /// No description provided for @customerMessageListSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼ごとのやり取り'**
  String get customerMessageListSubtitle;

  /// No description provided for @customerRequestListSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'進行状況をいつでも確認'**
  String get customerRequestListSubtitle;

  /// No description provided for @customerEmptyWorkspace.
  ///
  /// In ja, this message translates to:
  /// **'まだご依頼はありません。ホームから開発の相談をはじめましょう。'**
  String get customerEmptyWorkspace;

  /// No description provided for @customerViewDetails.
  ///
  /// In ja, this message translates to:
  /// **'詳細を確認する'**
  String get customerViewDetails;

  /// No description provided for @customerSendMessage.
  ///
  /// In ja, this message translates to:
  /// **'送信する'**
  String get customerSendMessage;

  /// No description provided for @customerMessageSent.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを送信しました'**
  String get customerMessageSent;

  /// No description provided for @customerConversationNote.
  ///
  /// In ja, this message translates to:
  /// **'このご依頼に関する運営とのやり取りです。'**
  String get customerConversationNote;

  /// No description provided for @customerNoMessages.
  ///
  /// In ja, this message translates to:
  /// **'メッセージはまだありません。'**
  String get customerNoMessages;

  /// No description provided for @customerMessageHint.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを入力'**
  String get customerMessageHint;

  /// No description provided for @customerProfileSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'アカウントと表示設定'**
  String get customerProfileSubtitle;

  /// No description provided for @customerInternalAccount.
  ///
  /// In ja, this message translates to:
  /// **'内部アカウント'**
  String get customerInternalAccount;

  /// No description provided for @customerCustomerAccount.
  ///
  /// In ja, this message translates to:
  /// **'お客様アカウント'**
  String get customerCustomerAccount;

  /// No description provided for @customerInternalAuthorization.
  ///
  /// In ja, this message translates to:
  /// **'内部の案件対応権限が付与されています。OPC 正式認定とは異なります。'**
  String get customerInternalAuthorization;

  /// No description provided for @customerAppearance.
  ///
  /// In ja, this message translates to:
  /// **'画面の表示'**
  String get customerAppearance;

  /// No description provided for @customerThemeSystem.
  ///
  /// In ja, this message translates to:
  /// **'システム'**
  String get customerThemeSystem;

  /// No description provided for @customerThemeLight.
  ///
  /// In ja, this message translates to:
  /// **'ライト'**
  String get customerThemeLight;

  /// No description provided for @customerThemeDark.
  ///
  /// In ja, this message translates to:
  /// **'ダーク'**
  String get customerThemeDark;

  /// No description provided for @customerBusinessRegion.
  ///
  /// In ja, this message translates to:
  /// **'日本向けサービス · 日本円（JPY）· 日本標準時（JST）'**
  String get customerBusinessRegion;

  /// No description provided for @customerAbout.
  ///
  /// In ja, this message translates to:
  /// **'このアプリについて'**
  String get customerAbout;

  /// No description provided for @customerAboutNote.
  ///
  /// In ja, this message translates to:
  /// **'OPC V1 / 0.1.0\nデモ環境です。業務データは端末のメモリ上に保存され、アプリの再起動で初期化されます。実際の認証・ファイル送信・決済は行いません。'**
  String get customerAboutNote;

  /// No description provided for @customerDemoScenarios.
  ///
  /// In ja, this message translates to:
  /// **'デモシナリオ'**
  String get customerDemoScenarios;

  /// No description provided for @customerLogout.
  ///
  /// In ja, this message translates to:
  /// **'ログアウト'**
  String get customerLogout;

  /// No description provided for @customerDemoSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'デモ操作 · 実際の管理操作ではありません'**
  String get customerDemoSubtitle;

  /// No description provided for @customerDemoNotice.
  ///
  /// In ja, this message translates to:
  /// **'バックエンドの審査結果を再現する開発用操作です。実運用では管理端とサーバーだけが審査・公開を実行します。'**
  String get customerDemoNotice;

  /// No description provided for @customerSimulateDelivery.
  ///
  /// In ja, this message translates to:
  /// **'内部確認後の納品公開を再現'**
  String get customerSimulateDelivery;

  /// No description provided for @customerSimulatePublication.
  ///
  /// In ja, this message translates to:
  /// **'審査・要件整理後の公開を再現'**
  String get customerSimulatePublication;

  /// No description provided for @customerDemoUpdated.
  ///
  /// In ja, this message translates to:
  /// **'デモの状態を更新しました'**
  String get customerDemoUpdated;

  /// No description provided for @customerFailNextAction.
  ///
  /// In ja, this message translates to:
  /// **'次の送信を失敗させる'**
  String get customerFailNextAction;

  /// No description provided for @customerFailNextNotice.
  ///
  /// In ja, this message translates to:
  /// **'次の送信でエラーを再現します。内容を保ったまま再試行できます。'**
  String get customerFailNextNotice;

  /// No description provided for @customerResetDemo.
  ///
  /// In ja, this message translates to:
  /// **'デモを初期状態に戻す'**
  String get customerResetDemo;

  /// No description provided for @customerResetDemoTitle.
  ///
  /// In ja, this message translates to:
  /// **'デモをリセットしますか？'**
  String get customerResetDemoTitle;

  /// No description provided for @customerResetDemoNotice.
  ///
  /// In ja, this message translates to:
  /// **'このデモで追加した登録・ご依頼・メッセージが消去され、ログイン画面に戻ります。'**
  String get customerResetDemoNotice;

  /// No description provided for @customerBack.
  ///
  /// In ja, this message translates to:
  /// **'戻る'**
  String get customerBack;

  /// No description provided for @customerReset.
  ///
  /// In ja, this message translates to:
  /// **'リセット'**
  String get customerReset;

  /// No description provided for @customerRequestCount.
  ///
  /// In ja, this message translates to:
  /// **'{count}件'**
  String customerRequestCount(int count);

  /// No description provided for @customerDeliveryPrompt.
  ///
  /// In ja, this message translates to:
  /// **'{id} · 納品内容をご確認ください'**
  String customerDeliveryPrompt(String id);

  /// No description provided for @customerRemoveAttachment.
  ///
  /// In ja, this message translates to:
  /// **'{name} を削除'**
  String customerRemoveAttachment(String name);

  /// No description provided for @customerAssistedDescription.
  ///
  /// In ja, this message translates to:
  /// **'実現したいこと：\n{original}\n\n利用する方：社内の社員（人数は相談時に確認）\n確認したいこと：利用する資料の形式、必要な機能、完成後の運用方法。'**
  String customerAssistedDescription(String original);

  /// No description provided for @customerReceivedDate.
  ///
  /// In ja, this message translates to:
  /// **'{year}年{month}月{day}日 {time}（JST）'**
  String customerReceivedDate(int year, int month, int day, String time);

  /// No description provided for @customerReceivedAt.
  ///
  /// In ja, this message translates to:
  /// **'受付：{date}'**
  String customerReceivedAt(String date);

  /// No description provided for @customerMessageDate.
  ///
  /// In ja, this message translates to:
  /// **'{month}月{day}日 {time} JST'**
  String customerMessageDate(int month, int day, String time);

  /// No description provided for @customerTimingMonth.
  ///
  /// In ja, this message translates to:
  /// **'1か月以内を希望'**
  String get customerTimingMonth;

  /// No description provided for @customerTimingQuarter.
  ///
  /// In ja, this message translates to:
  /// **'2〜3か月以内を希望'**
  String get customerTimingQuarter;

  /// No description provided for @customerTimingDiscuss.
  ///
  /// In ja, this message translates to:
  /// **'時期は相談したい'**
  String get customerTimingDiscuss;

  /// No description provided for @customerBudgetDiscuss.
  ///
  /// In ja, this message translates to:
  /// **'相談して決めたい'**
  String get customerBudgetDiscuss;

  /// No description provided for @customerBudgetUnder100k.
  ///
  /// In ja, this message translates to:
  /// **'10万円未満'**
  String get customerBudgetUnder100k;

  /// No description provided for @customerBudget100to300k.
  ///
  /// In ja, this message translates to:
  /// **'10万〜30万円'**
  String get customerBudget100to300k;

  /// No description provided for @customerBudget300to500k.
  ///
  /// In ja, this message translates to:
  /// **'30万〜50万円'**
  String get customerBudget300to500k;

  /// No description provided for @customerBudgetOver500k.
  ///
  /// In ja, this message translates to:
  /// **'50万円以上'**
  String get customerBudgetOver500k;

  /// No description provided for @customerLanguage.
  ///
  /// In ja, this message translates to:
  /// **'言語'**
  String get customerLanguage;

  /// No description provided for @customerLanguageNote.
  ///
  /// In ja, this message translates to:
  /// **'表示言語のみを切り替えます。ご依頼やメッセージの原文・通貨・時刻・権限は変わりません。'**
  String get customerLanguageNote;

  /// No description provided for @fileSaveToPhone.
  ///
  /// In ja, this message translates to:
  /// **'端末のファイルに保存'**
  String get fileSaveToPhone;

  /// No description provided for @filePreviewFailed.
  ///
  /// In ja, this message translates to:
  /// **'プレビューできません。再試行するか、原本を端末に保存して開いてください。'**
  String get filePreviewFailed;

  /// No description provided for @fileInlineAttachment.
  ///
  /// In ja, this message translates to:
  /// **'ファイルを表示'**
  String get fileInlineAttachment;

  /// No description provided for @fileOriginal.
  ///
  /// In ja, this message translates to:
  /// **'原本をダウンロード'**
  String get fileOriginal;

  /// No description provided for @mediaFullscreen.
  ///
  /// In ja, this message translates to:
  /// **'全画面再生'**
  String get mediaFullscreen;

  /// No description provided for @mediaExitFullscreen.
  ///
  /// In ja, this message translates to:
  /// **'全画面を終了'**
  String get mediaExitFullscreen;

  /// No description provided for @mediaPause.
  ///
  /// In ja, this message translates to:
  /// **'一時停止'**
  String get mediaPause;

  /// No description provided for @mediaReplay.
  ///
  /// In ja, this message translates to:
  /// **'もう一度再生'**
  String get mediaReplay;

  /// No description provided for @mediaBackward.
  ///
  /// In ja, this message translates to:
  /// **'10秒戻る'**
  String get mediaBackward;

  /// No description provided for @mediaForward.
  ///
  /// In ja, this message translates to:
  /// **'10秒進む'**
  String get mediaForward;

  /// No description provided for @mediaMute.
  ///
  /// In ja, this message translates to:
  /// **'ミュート'**
  String get mediaMute;

  /// No description provided for @mediaUnmute.
  ///
  /// In ja, this message translates to:
  /// **'ミュートを解除'**
  String get mediaUnmute;

  /// No description provided for @mediaSpeed.
  ///
  /// In ja, this message translates to:
  /// **'再生速度'**
  String get mediaSpeed;

  /// No description provided for @homeIntro.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼・進捗・パートナーからの連絡をまとめて確認'**
  String get homeIntro;

  /// No description provided for @homeGreeting.
  ///
  /// In ja, this message translates to:
  /// **'{name} さん、こんにちは'**
  String homeGreeting(String name);

  /// No description provided for @homeOverview.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクトの概要'**
  String get homeOverview;

  /// No description provided for @homeSummary.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼 {requests} 件 · 協業プロジェクト {projects} 件'**
  String homeSummary(int requests, int projects);

  /// No description provided for @homeReviewing.
  ///
  /// In ja, this message translates to:
  /// **'確認中'**
  String get homeReviewing;

  /// No description provided for @homeActive.
  ///
  /// In ja, this message translates to:
  /// **'進行中'**
  String get homeActive;

  /// No description provided for @homeAcceptance.
  ///
  /// In ja, this message translates to:
  /// **'検収待ち'**
  String get homeAcceptance;

  /// No description provided for @homeCompleted.
  ///
  /// In ja, this message translates to:
  /// **'完了'**
  String get homeCompleted;

  /// No description provided for @homeAll.
  ///
  /// In ja, this message translates to:
  /// **'すべて見る'**
  String get homeAll;

  /// No description provided for @homeClearFilter.
  ///
  /// In ja, this message translates to:
  /// **'すべての依頼を表示'**
  String get homeClearFilter;

  /// No description provided for @homeTodos.
  ///
  /// In ja, this message translates to:
  /// **'ご対応が必要なこと'**
  String get homeTodos;

  /// No description provided for @homeNoTodos.
  ///
  /// In ja, this message translates to:
  /// **'現在、ご対応が必要なことはありません'**
  String get homeNoTodos;

  /// No description provided for @homeNoTodosHelp.
  ///
  /// In ja, this message translates to:
  /// **'追加情報、協業条件、納品内容の確認が必要な場合に表示します。'**
  String get homeNoTodosHelp;

  /// No description provided for @homeReplyHelp.
  ///
  /// In ja, this message translates to:
  /// **'運営から追加の確認があります。ご回答後に手続きを進めます。'**
  String get homeReplyHelp;

  /// No description provided for @homeAgreementHelp.
  ///
  /// In ja, this message translates to:
  /// **'範囲・見積もり・納品条件を確認し、現在の協業条件に同意してください。'**
  String get homeAgreementHelp;

  /// No description provided for @homeAcceptanceHelp.
  ///
  /// In ja, this message translates to:
  /// **'納品内容を公開しました。内容を確認し、検収または修正依頼に進んでください。'**
  String get homeAcceptanceHelp;

  /// No description provided for @homeReviews.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼の確認・公開状況'**
  String get homeReviews;

  /// No description provided for @homeNoReviews.
  ///
  /// In ja, this message translates to:
  /// **'確認中・協業待ちのご依頼はありません'**
  String get homeNoReviews;

  /// No description provided for @homeReviewHelp.
  ///
  /// In ja, this message translates to:
  /// **'運営がご依頼を確認し、技術的な範囲を整理しています。'**
  String get homeReviewHelp;

  /// No description provided for @homePublishedHelp.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼を公開しました。協業関係の確定をお待ちください。'**
  String get homePublishedHelp;

  /// No description provided for @homeProjects.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクトの進捗'**
  String get homeProjects;

  /// No description provided for @homeNoProjects.
  ///
  /// In ja, this message translates to:
  /// **'進行中の協業プロジェクトはありません'**
  String get homeNoProjects;

  /// No description provided for @homeNoProjectsHelp.
  ///
  /// In ja, this message translates to:
  /// **'協業確定後、現在の段階・納期・連絡内容を確認できます。'**
  String get homeNoProjectsHelp;

  /// No description provided for @homeStageReview.
  ///
  /// In ja, this message translates to:
  /// **'依頼確認'**
  String get homeStageReview;

  /// No description provided for @homeStageAgreement.
  ///
  /// In ja, this message translates to:
  /// **'協業確認'**
  String get homeStageAgreement;

  /// No description provided for @homeStageDevelopment.
  ///
  /// In ja, this message translates to:
  /// **'開発・納品'**
  String get homeStageDevelopment;

  /// No description provided for @homeStageAcceptance.
  ///
  /// In ja, this message translates to:
  /// **'検収'**
  String get homeStageAcceptance;

  /// No description provided for @homeWorkingHelp.
  ///
  /// In ja, this message translates to:
  /// **'パートナーが合意した範囲で作業を進めています。連絡や成果を確認できます。'**
  String get homeWorkingHelp;

  /// No description provided for @homeInternalHelp.
  ///
  /// In ja, this message translates to:
  /// **'成果物を内部確認中です。公開後に内容の確認・検収ができます。'**
  String get homeInternalHelp;

  /// No description provided for @homeRevisionHelp.
  ///
  /// In ja, this message translates to:
  /// **'パートナーが修正に対応しています。連絡内容をご確認ください。'**
  String get homeRevisionHelp;

  /// No description provided for @homeFeedback.
  ///
  /// In ja, this message translates to:
  /// **'パートナーからの最新連絡'**
  String get homeFeedback;

  /// No description provided for @homeNoFeedback.
  ///
  /// In ja, this message translates to:
  /// **'パートナーからの連絡はまだありません'**
  String get homeNoFeedback;

  /// No description provided for @homeNoFeedbackHelp.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクトの担当パートナーから届いたメッセージをまとめて表示します。'**
  String get homeNoFeedbackHelp;

  /// No description provided for @homeProvider.
  ///
  /// In ja, this message translates to:
  /// **'担当パートナー'**
  String get homeProvider;

  /// No description provided for @homeUnread.
  ///
  /// In ja, this message translates to:
  /// **'未読の通知 {count} 件'**
  String homeUnread(int count);

  /// No description provided for @homeStart.
  ///
  /// In ja, this message translates to:
  /// **'最初のご依頼から始めましょう'**
  String get homeStart;

  /// No description provided for @homeStartHelp.
  ///
  /// In ja, this message translates to:
  /// **'解決したいことをお聞かせください。確認・開発・納品の状況をここで追跡できます。'**
  String get homeStartHelp;

  /// No description provided for @homeDraft.
  ///
  /// In ja, this message translates to:
  /// **'保存したご相談の入力を続ける'**
  String get homeDraft;

  /// No description provided for @homeMoreTodos.
  ///
  /// In ja, this message translates to:
  /// **'対応事項をすべて見る'**
  String get homeMoreTodos;

  /// No description provided for @previewTitle.
  ///
  /// In ja, this message translates to:
  /// **'プレビュー'**
  String get previewTitle;

  /// No description provided for @previewImageTitle.
  ///
  /// In ja, this message translates to:
  /// **'画像を見る'**
  String get previewImageTitle;

  /// No description provided for @previewVideoTitle.
  ///
  /// In ja, this message translates to:
  /// **'動画を再生'**
  String get previewVideoTitle;

  /// No description provided for @previewDocumentTitle.
  ///
  /// In ja, this message translates to:
  /// **'文書プレビュー'**
  String get previewDocumentTitle;

  /// No description provided for @previewPdfTitle.
  ///
  /// In ja, this message translates to:
  /// **'PDF プレビュー'**
  String get previewPdfTitle;

  /// No description provided for @previewTableTitle.
  ///
  /// In ja, this message translates to:
  /// **'表プレビュー'**
  String get previewTableTitle;

  /// No description provided for @previewSlidesTitle.
  ///
  /// In ja, this message translates to:
  /// **'スライドプレビュー'**
  String get previewSlidesTitle;

  /// No description provided for @previewTextTitle.
  ///
  /// In ja, this message translates to:
  /// **'テキストプレビュー'**
  String get previewTextTitle;

  /// No description provided for @previewReadOnly.
  ///
  /// In ja, this message translates to:
  /// **'読み取り専用'**
  String get previewReadOnly;

  /// No description provided for @previewPrevious.
  ///
  /// In ja, this message translates to:
  /// **'前へ'**
  String get previewPrevious;

  /// No description provided for @previewNext.
  ///
  /// In ja, this message translates to:
  /// **'次へ'**
  String get previewNext;

  /// No description provided for @previewZoomIn.
  ///
  /// In ja, this message translates to:
  /// **'拡大'**
  String get previewZoomIn;

  /// No description provided for @previewZoomOut.
  ///
  /// In ja, this message translates to:
  /// **'縮小'**
  String get previewZoomOut;

  /// No description provided for @previewResetZoom.
  ///
  /// In ja, this message translates to:
  /// **'拡大率をリセット'**
  String get previewResetZoom;

  /// No description provided for @previewImageHint.
  ///
  /// In ja, this message translates to:
  /// **'ピンチで拡大。拡大していない時はスワイプ、矢印やサムネイルで画像を切り替えます。'**
  String get previewImageHint;

  /// No description provided for @previewPages.
  ///
  /// In ja, this message translates to:
  /// **'ページへ移動'**
  String get previewPages;

  /// No description provided for @previewPageNumber.
  ///
  /// In ja, this message translates to:
  /// **'ページ番号'**
  String get previewPageNumber;

  /// No description provided for @previewGo.
  ///
  /// In ja, this message translates to:
  /// **'移動'**
  String get previewGo;

  /// No description provided for @previewCancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get previewCancel;

  /// No description provided for @previewDocumentHint.
  ///
  /// In ja, this message translates to:
  /// **'上下にスクロールして閲覧。ページ番号から移動できます。'**
  String get previewDocumentHint;

  /// No description provided for @previewFixtureNotice.
  ///
  /// In ja, this message translates to:
  /// **'同梱のサンプル資料を表示しています。任意の Office ファイルを変換する機能はまだ接続されていません。'**
  String get previewFixtureNotice;

  /// No description provided for @previewFullscreen.
  ///
  /// In ja, this message translates to:
  /// **'全画面'**
  String get previewFullscreen;

  /// No description provided for @previewExitFullscreen.
  ///
  /// In ja, this message translates to:
  /// **'全画面を閉じる'**
  String get previewExitFullscreen;

  /// No description provided for @previewSlideHint.
  ///
  /// In ja, this message translates to:
  /// **'左右のボタンやサムネイルでページを切り替えます。'**
  String get previewSlideHint;

  /// No description provided for @previewOriginal.
  ///
  /// In ja, this message translates to:
  /// **'原文'**
  String get previewOriginal;

  /// No description provided for @previewFormatted.
  ///
  /// In ja, this message translates to:
  /// **'書式付き'**
  String get previewFormatted;

  /// No description provided for @previewTextSize.
  ///
  /// In ja, this message translates to:
  /// **'文字サイズ'**
  String get previewTextSize;

  /// No description provided for @previewSmallerText.
  ///
  /// In ja, this message translates to:
  /// **'文字を小さく'**
  String get previewSmallerText;

  /// No description provided for @previewLargerText.
  ///
  /// In ja, this message translates to:
  /// **'文字を大きく'**
  String get previewLargerText;

  /// No description provided for @previewTextHint.
  ///
  /// In ja, this message translates to:
  /// **'内容は原文のまま表示します。TXT は自動改行、Markdown は見出し・箇条書き・コードなどの基本書式に対応します。'**
  String get previewTextHint;

  /// No description provided for @previewSearch.
  ///
  /// In ja, this message translates to:
  /// **'表内を検索'**
  String get previewSearch;

  /// No description provided for @previewClearSearch.
  ///
  /// In ja, this message translates to:
  /// **'検索をクリア'**
  String get previewClearSearch;

  /// No description provided for @previewNoMatches.
  ///
  /// In ja, this message translates to:
  /// **'一致するセルはありません。'**
  String get previewNoMatches;

  /// No description provided for @previewTableHint.
  ///
  /// In ja, this message translates to:
  /// **'左右にスクロールして列を確認できます。CSV は単一の表として表示します。'**
  String get previewTableHint;

  /// No description provided for @previewPlay.
  ///
  /// In ja, this message translates to:
  /// **'再生'**
  String get previewPlay;

  /// No description provided for @previewPause.
  ///
  /// In ja, this message translates to:
  /// **'一時停止'**
  String get previewPause;

  /// No description provided for @previewMute.
  ///
  /// In ja, this message translates to:
  /// **'ミュート'**
  String get previewMute;

  /// No description provided for @previewUnmute.
  ///
  /// In ja, this message translates to:
  /// **'ミュート解除'**
  String get previewUnmute;

  /// No description provided for @previewSeek.
  ///
  /// In ja, this message translates to:
  /// **'再生位置'**
  String get previewSeek;

  /// No description provided for @previewVideoLoading.
  ///
  /// In ja, this message translates to:
  /// **'動画を読み込んでいます'**
  String get previewVideoLoading;

  /// No description provided for @previewVideoFailed.
  ///
  /// In ja, this message translates to:
  /// **'動画を再生できませんでした'**
  String get previewVideoFailed;

  /// No description provided for @previewVideoHint.
  ///
  /// In ja, this message translates to:
  /// **'タップして再生します。自動再生はしません。'**
  String get previewVideoHint;

  /// No description provided for @previewPreparing.
  ///
  /// In ja, this message translates to:
  /// **'プレビューを準備中'**
  String get previewPreparing;

  /// No description provided for @previewPreparingHint.
  ///
  /// In ja, this message translates to:
  /// **'原本はダウンロードできます。準備状況を再確認できます。'**
  String get previewPreparingHint;

  /// No description provided for @previewCheckPreparation.
  ///
  /// In ja, this message translates to:
  /// **'準備状況を確認'**
  String get previewCheckPreparation;

  /// No description provided for @previewFailed.
  ///
  /// In ja, this message translates to:
  /// **'プレビューできませんでした'**
  String get previewFailed;

  /// No description provided for @previewFailedHint.
  ///
  /// In ja, this message translates to:
  /// **'再試行するか、原本をダウンロードして確認してください。'**
  String get previewFailedHint;

  /// No description provided for @previewRetry.
  ///
  /// In ja, this message translates to:
  /// **'再試行'**
  String get previewRetry;

  /// No description provided for @previewUnsupported.
  ///
  /// In ja, this message translates to:
  /// **'プレビュー非対応'**
  String get previewUnsupported;

  /// No description provided for @previewUnsupportedHint.
  ///
  /// In ja, this message translates to:
  /// **'原本をダウンロードして確認できます。'**
  String get previewUnsupportedHint;

  /// No description provided for @previewAccessDenied.
  ///
  /// In ja, this message translates to:
  /// **'この資料へのアクセス権がありません'**
  String get previewAccessDenied;

  /// No description provided for @previewAccessDeniedHint.
  ///
  /// In ja, this message translates to:
  /// **'閲覧を停止しました。必要な場合は運営担当者にお問い合わせください。'**
  String get previewAccessDeniedHint;

  /// No description provided for @previewEmpty.
  ///
  /// In ja, this message translates to:
  /// **'表示できる内容がありません'**
  String get previewEmpty;

  /// No description provided for @previewImageFailed.
  ///
  /// In ja, this message translates to:
  /// **'画像を読み込めませんでした'**
  String get previewImageFailed;

  /// No description provided for @previewSelectedCell.
  ///
  /// In ja, this message translates to:
  /// **'選択したセル'**
  String get previewSelectedCell;

  /// No description provided for @previewImageCount.
  ///
  /// In ja, this message translates to:
  /// **'画像 {current} / {total}'**
  String previewImageCount(int current, int total);

  /// No description provided for @previewPageCount.
  ///
  /// In ja, this message translates to:
  /// **'{current} / {total}'**
  String previewPageCount(int current, int total);

  /// No description provided for @previewPageRange.
  ///
  /// In ja, this message translates to:
  /// **'1〜{total} のページ番号を入力してください'**
  String previewPageRange(int total);

  /// No description provided for @previewSearchMatches.
  ///
  /// In ja, this message translates to:
  /// **'一致するセル {count} 件'**
  String previewSearchMatches(int count);

  /// No description provided for @previewSheetCount.
  ///
  /// In ja, this message translates to:
  /// **'{count} シート'**
  String previewSheetCount(int count);

  /// No description provided for @previewThumbnail.
  ///
  /// In ja, this message translates to:
  /// **'{index} ページを開く'**
  String previewThumbnail(int index);

  /// No description provided for @projectTitle.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクト'**
  String get projectTitle;

  /// No description provided for @projectProviderSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'担当プロジェクトのワークスペース'**
  String get projectProviderSubtitle;

  /// No description provided for @projectCustomerSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼の進行状況を確認しましょう'**
  String get projectCustomerSubtitle;

  /// No description provided for @projectInfoTitle.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクト情報'**
  String get projectInfoTitle;

  /// No description provided for @projectInternalReviewPending.
  ///
  /// In ja, this message translates to:
  /// **'提出内容を運営が確認中です。お客様にはまだ公開されていません。'**
  String get projectInternalReviewPending;

  /// No description provided for @projectAwaitingOperations.
  ///
  /// In ja, this message translates to:
  /// **'運営の確認待ち'**
  String get projectAwaitingOperations;

  /// No description provided for @projectSubmitRevision.
  ///
  /// In ja, this message translates to:
  /// **'修正版を提出する'**
  String get projectSubmitRevision;

  /// No description provided for @projectSubmitDelivery.
  ///
  /// In ja, this message translates to:
  /// **'成果物を提出する'**
  String get projectSubmitDelivery;

  /// No description provided for @projectReviewDelivery.
  ///
  /// In ja, this message translates to:
  /// **'納品内容を確認する'**
  String get projectReviewDelivery;

  /// No description provided for @projectSendMessage.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを送る'**
  String get projectSendMessage;

  /// No description provided for @projectConsultation.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクトの相談'**
  String get projectConsultation;

  /// No description provided for @projectConsultationHint.
  ///
  /// In ja, this message translates to:
  /// **'確認したいことはメッセージからお知らせください。'**
  String get projectConsultationHint;

  /// No description provided for @projectOpenMessages.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを開く'**
  String get projectOpenMessages;

  /// No description provided for @projectNoMessages.
  ///
  /// In ja, this message translates to:
  /// **'まだメッセージはありません。'**
  String get projectNoMessages;

  /// No description provided for @projectNoProviderDeliveries.
  ///
  /// In ja, this message translates to:
  /// **'提出済みの成果物はまだありません。下のボタンから提出できます。'**
  String get projectNoProviderDeliveries;

  /// No description provided for @projectNoCustomerDeliveries.
  ///
  /// In ja, this message translates to:
  /// **'お客様向けの納品ファイルは、運営の確認後に表示されます。'**
  String get projectNoCustomerDeliveries;

  /// No description provided for @projectEditFixedVersion.
  ///
  /// In ja, this message translates to:
  /// **'固定バージョンを編集'**
  String get projectEditFixedVersion;

  /// No description provided for @projectFixedVersion.
  ///
  /// In ja, this message translates to:
  /// **'リリース・固定コミット'**
  String get projectFixedVersion;

  /// No description provided for @projectFixedVersionHint.
  ///
  /// In ja, this message translates to:
  /// **'例：v0.3.0 · 8f3a2c1'**
  String get projectFixedVersionHint;

  /// No description provided for @projectFixedVersionHelp.
  ///
  /// In ja, this message translates to:
  /// **'提出するソースを特定できるタグ・コミットを入力してください。サンプルの記録です。'**
  String get projectFixedVersionHelp;

  /// No description provided for @projectSave.
  ///
  /// In ja, this message translates to:
  /// **'保存する'**
  String get projectSave;

  /// No description provided for @projectSubmitted.
  ///
  /// In ja, this message translates to:
  /// **'運営に確認を依頼しました。お客様への公開は内部確認後です。'**
  String get projectSubmitted;

  /// No description provided for @projectDeliveryTitle.
  ///
  /// In ja, this message translates to:
  /// **'成果物の提出'**
  String get projectDeliveryTitle;

  /// No description provided for @projectDeliveryUnauthorized.
  ///
  /// In ja, this message translates to:
  /// **'このプロジェクトの担当者だけが成果物を提出できます。'**
  String get projectDeliveryUnauthorized;

  /// No description provided for @projectDeliverySubtitle.
  ///
  /// In ja, this message translates to:
  /// **'確認できる形で、成果をまとめましょう'**
  String get projectDeliverySubtitle;

  /// No description provided for @projectSubmitting.
  ///
  /// In ja, this message translates to:
  /// **'提出しています…'**
  String get projectSubmitting;

  /// No description provided for @projectRequestReview.
  ///
  /// In ja, this message translates to:
  /// **'運営に確認を依頼する'**
  String get projectRequestReview;

  /// No description provided for @projectSourceCode.
  ///
  /// In ja, this message translates to:
  /// **'ソースコード'**
  String get projectSourceCode;

  /// No description provided for @projectRequired.
  ///
  /// In ja, this message translates to:
  /// **'必須'**
  String get projectRequired;

  /// No description provided for @projectSourceSelected.
  ///
  /// In ja, this message translates to:
  /// **'18.4 MB · 選択済み'**
  String get projectSourceSelected;

  /// No description provided for @projectGuideAndTest.
  ///
  /// In ja, this message translates to:
  /// **'操作説明・確認資料'**
  String get projectGuideAndTest;

  /// No description provided for @projectGuideSelected.
  ///
  /// In ja, this message translates to:
  /// **'1.2 MB · 選択済み'**
  String get projectGuideSelected;

  /// No description provided for @projectTestSelected.
  ///
  /// In ja, this message translates to:
  /// **'84 KB · 選択済み'**
  String get projectTestSelected;

  /// No description provided for @projectChanges.
  ///
  /// In ja, this message translates to:
  /// **'今回の変更点'**
  String get projectChanges;

  /// No description provided for @projectChangesHint.
  ///
  /// In ja, this message translates to:
  /// **'変更内容と確認方法を入力してください'**
  String get projectChangesHint;

  /// No description provided for @projectChangesRequired.
  ///
  /// In ja, this message translates to:
  /// **'変更内容を入力してください'**
  String get projectChangesRequired;

  /// No description provided for @projectDeliveryReviewNotice.
  ///
  /// In ja, this message translates to:
  /// **'提出後、運営が内容を確認します。\nお客様への公開は、内部確認後に行います。'**
  String get projectDeliveryReviewNotice;

  /// No description provided for @projectAttachmentsNotice.
  ///
  /// In ja, this message translates to:
  /// **'添付はサンプル名のみです。実ファイルのアップロード・テスト実行は行いません。'**
  String get projectAttachmentsNotice;

  /// No description provided for @projectAcceptConfirmTitle.
  ///
  /// In ja, this message translates to:
  /// **'検収を完了しますか？'**
  String get projectAcceptConfirmTitle;

  /// No description provided for @projectBack.
  ///
  /// In ja, this message translates to:
  /// **'戻る'**
  String get projectBack;

  /// No description provided for @projectCompleteAcceptance.
  ///
  /// In ja, this message translates to:
  /// **'検収を完了する'**
  String get projectCompleteAcceptance;

  /// No description provided for @projectAccepted.
  ///
  /// In ja, this message translates to:
  /// **'検収が完了しました。ご確認ありがとうございます。'**
  String get projectAccepted;

  /// No description provided for @projectRequestRevision.
  ///
  /// In ja, this message translates to:
  /// **'修正を依頼する'**
  String get projectRequestRevision;

  /// No description provided for @projectRevisionContent.
  ///
  /// In ja, this message translates to:
  /// **'修正してほしい内容'**
  String get projectRevisionContent;

  /// No description provided for @projectRevisionHint.
  ///
  /// In ja, this message translates to:
  /// **'画面・操作手順・期待した結果をお知らせください'**
  String get projectRevisionHint;

  /// No description provided for @projectRevisionHelp.
  ///
  /// In ja, this message translates to:
  /// **'運営がご依頼を確認します。修正依頼後は、新しい公開版の到着をお待ちください。'**
  String get projectRevisionHelp;

  /// No description provided for @projectRevisionRequested.
  ///
  /// In ja, this message translates to:
  /// **'修正のご依頼を記録しました。運営が内容を確認します。'**
  String get projectRevisionRequested;

  /// No description provided for @projectAcceptanceTitle.
  ///
  /// In ja, this message translates to:
  /// **'納品内容の確認'**
  String get projectAcceptanceTitle;

  /// No description provided for @projectNoPublishedDelivery.
  ///
  /// In ja, this message translates to:
  /// **'お客様向けに公開された納品内容はまだありません。運営の確認後に表示されます。'**
  String get projectNoPublishedDelivery;

  /// No description provided for @projectAcceptanceSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'仕上がりを、ご自身で確かめましょう'**
  String get projectAcceptanceSubtitle;

  /// No description provided for @projectAcceptedNotice.
  ///
  /// In ja, this message translates to:
  /// **'公開版の検収が完了しました。'**
  String get projectAcceptedNotice;

  /// No description provided for @projectRevisionPendingNotice.
  ///
  /// In ja, this message translates to:
  /// **'修正依頼を受け付けました。新しい公開版をお待ちください。'**
  String get projectRevisionPendingNotice;

  /// No description provided for @projectCheckAllHint.
  ///
  /// In ja, this message translates to:
  /// **'すべての項目を確認すると、検収を完了できます。'**
  String get projectCheckAllHint;

  /// No description provided for @projectAcceptanceComplete.
  ///
  /// In ja, this message translates to:
  /// **'検収完了'**
  String get projectAcceptanceComplete;

  /// No description provided for @projectWatchDemo.
  ///
  /// In ja, this message translates to:
  /// **'操作デモを見る'**
  String get projectWatchDemo;

  /// No description provided for @projectDemoSummary.
  ///
  /// In ja, this message translates to:
  /// **'登録から対応完了までをご案内'**
  String get projectDemoSummary;

  /// No description provided for @projectPublishedFiles.
  ///
  /// In ja, this message translates to:
  /// **'納品ファイル・操作説明書'**
  String get projectPublishedFiles;

  /// No description provided for @projectPublishedFileCount.
  ///
  /// In ja, this message translates to:
  /// **'公開版の資料 3件'**
  String get projectPublishedFileCount;

  /// No description provided for @projectAcceptanceChecklist.
  ///
  /// In ja, this message translates to:
  /// **'ご確認いただきたいこと'**
  String get projectAcceptanceChecklist;

  /// No description provided for @projectRevisionReviewing.
  ///
  /// In ja, this message translates to:
  /// **'修正のご依頼を運営が確認しています。'**
  String get projectRevisionReviewing;

  /// No description provided for @projectAcceptedFilesNotice.
  ///
  /// In ja, this message translates to:
  /// **'ご確認ありがとうございます。納品ファイルは引き続きこの画面から確認できます。'**
  String get projectAcceptedFilesNotice;

  /// No description provided for @projectRevisionInvitation.
  ///
  /// In ja, this message translates to:
  /// **'気になる点は、修正のご依頼からお知らせください。運営が内容を確認します。'**
  String get projectRevisionInvitation;

  /// No description provided for @projectProgressTab.
  ///
  /// In ja, this message translates to:
  /// **'進行状況'**
  String get projectProgressTab;

  /// No description provided for @projectMessagesTab.
  ///
  /// In ja, this message translates to:
  /// **'メッセージ'**
  String get projectMessagesTab;

  /// No description provided for @projectFilesTab.
  ///
  /// In ja, this message translates to:
  /// **'ファイル'**
  String get projectFilesTab;

  /// No description provided for @projectMilestones.
  ///
  /// In ja, this message translates to:
  /// **'マイルストーン'**
  String get projectMilestones;

  /// No description provided for @projectRequirementsMilestone.
  ///
  /// In ja, this message translates to:
  /// **'要件確認'**
  String get projectRequirementsMilestone;

  /// No description provided for @projectDevelopmentMilestone.
  ///
  /// In ja, this message translates to:
  /// **'開発'**
  String get projectDevelopmentMilestone;

  /// No description provided for @projectInternalMilestone.
  ///
  /// In ja, this message translates to:
  /// **'内部確認'**
  String get projectInternalMilestone;

  /// No description provided for @projectCustomerMilestone.
  ///
  /// In ja, this message translates to:
  /// **'お客様確認'**
  String get projectCustomerMilestone;

  /// No description provided for @projectRevisionMilestoneDescription.
  ///
  /// In ja, this message translates to:
  /// **'ご依頼いただいた修正内容を確認'**
  String get projectRevisionMilestoneDescription;

  /// No description provided for @projectRequirementsMilestoneDescription.
  ///
  /// In ja, this message translates to:
  /// **'対象範囲と確認基準を確定'**
  String get projectRequirementsMilestoneDescription;

  /// No description provided for @projectDevelopmentMilestoneDescription.
  ///
  /// In ja, this message translates to:
  /// **'検索画面と回答機能を実装中'**
  String get projectDevelopmentMilestoneDescription;

  /// No description provided for @projectInternalMilestoneDescription.
  ///
  /// In ja, this message translates to:
  /// **'運営が品質・資料を確認'**
  String get projectInternalMilestoneDescription;

  /// No description provided for @projectCustomerMilestoneDescription.
  ///
  /// In ja, this message translates to:
  /// **'公開された納品内容を検収'**
  String get projectCustomerMilestoneDescription;

  /// No description provided for @projectMessageAvatar.
  ///
  /// In ja, this message translates to:
  /// **'メ'**
  String get projectMessageAvatar;

  /// No description provided for @projectReplaceFile.
  ///
  /// In ja, this message translates to:
  /// **'ファイルを差し替える'**
  String get projectReplaceFile;

  /// No description provided for @projectDeliveryPublished.
  ///
  /// In ja, this message translates to:
  /// **'お客様公開済み'**
  String get projectDeliveryPublished;

  /// No description provided for @projectDeliveryInternal.
  ///
  /// In ja, this message translates to:
  /// **'内部確認用'**
  String get projectDeliveryInternal;

  /// No description provided for @projectGuideMetadata.
  ///
  /// In ja, this message translates to:
  /// **'操作説明'**
  String get projectGuideMetadata;

  /// No description provided for @projectTestMetadata.
  ///
  /// In ja, this message translates to:
  /// **'確認資料'**
  String get projectTestMetadata;

  /// No description provided for @projectMessageSent.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを送信しました'**
  String get projectMessageSent;

  /// No description provided for @projectMessageHint.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを入力'**
  String get projectMessageHint;

  /// No description provided for @projectMessageRequired.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを入力してください'**
  String get projectMessageRequired;

  /// No description provided for @projectMessageSendTooltip.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを送信'**
  String get projectMessageSendTooltip;

  /// No description provided for @projectSelectFile.
  ///
  /// In ja, this message translates to:
  /// **'ファイルを選択'**
  String get projectSelectFile;

  /// No description provided for @projectFilePickerNotice.
  ///
  /// In ja, this message translates to:
  /// **'サンプル名を選択・編集できます。実際のファイルは送信されません。'**
  String get projectFilePickerNotice;

  /// No description provided for @projectSampleFilename.
  ///
  /// In ja, this message translates to:
  /// **'サンプルファイル名'**
  String get projectSampleFilename;

  /// No description provided for @projectFilenameRequired.
  ///
  /// In ja, this message translates to:
  /// **'ファイル名を入力してください'**
  String get projectFilenameRequired;

  /// No description provided for @projectUseSample.
  ///
  /// In ja, this message translates to:
  /// **'このサンプルを使用する'**
  String get projectUseSample;

  /// No description provided for @projectCancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get projectCancel;

  /// No description provided for @projectClose.
  ///
  /// In ja, this message translates to:
  /// **'閉じる'**
  String get projectClose;

  /// No description provided for @projectSourcePreview.
  ///
  /// In ja, this message translates to:
  /// **'ソースコード一式\n\n・アプリケーションのソース\n・環境設定のサンプル\n・起動手順（README）\n\n固定バージョンに紐づく構成例です。この画面ではコードの実行やダウンロードを行いません。'**
  String get projectSourcePreview;

  /// No description provided for @projectGuidePreview.
  ///
  /// In ja, this message translates to:
  /// **'操作説明のサンプル\n\n1. 一覧画面で登録済みの項目を確認します。\n2. キーワードを入力して検索します。\n3. 詳細画面で内容を確認・更新します。\n4. 保存後、一覧で変更結果を確認します。'**
  String get projectGuidePreview;

  /// No description provided for @projectTestPreview.
  ///
  /// In ja, this message translates to:
  /// **'確認資料のサンプル\n\n・登録・検索シナリオ\n・更新・保存シナリオ\n・操作説明の確認\n\nこの資料は画面確認用の合成データです。実際のテスト結果や品質保証を示すものではありません。'**
  String get projectTestPreview;

  /// No description provided for @projectFileAccessNotice.
  ///
  /// In ja, this message translates to:
  /// **'実ファイルの取得・配信は、今後の API 接続で対応します。'**
  String get projectFileAccessNotice;

  /// No description provided for @projectDemoTitle.
  ///
  /// In ja, this message translates to:
  /// **'操作デモ'**
  String get projectDemoTitle;

  /// No description provided for @projectDemoRegister.
  ///
  /// In ja, this message translates to:
  /// **'1. 問い合わせを登録'**
  String get projectDemoRegister;

  /// No description provided for @projectDemoSearch.
  ///
  /// In ja, this message translates to:
  /// **'2. 一覧から検索'**
  String get projectDemoSearch;

  /// No description provided for @projectDemoUpdate.
  ///
  /// In ja, this message translates to:
  /// **'3. 対応状況を更新'**
  String get projectDemoUpdate;

  /// No description provided for @projectDemoRegisterDescription.
  ///
  /// In ja, this message translates to:
  /// **'件名と内容を入力して保存すると、一覧に新しい問い合わせが表示されます。'**
  String get projectDemoRegisterDescription;

  /// No description provided for @projectDemoSearchDescription.
  ///
  /// In ja, this message translates to:
  /// **'キーワードで対象を絞り込み、問い合わせの詳細を確認します。'**
  String get projectDemoSearchDescription;

  /// No description provided for @projectDemoUpdateDescription.
  ///
  /// In ja, this message translates to:
  /// **'担当者と対応状況を変更し、保存後の内容を一覧で確認します。'**
  String get projectDemoUpdateDescription;

  /// No description provided for @projectDemoRestart.
  ///
  /// In ja, this message translates to:
  /// **'最初から見る'**
  String get projectDemoRestart;

  /// No description provided for @projectDemoNext.
  ///
  /// In ja, this message translates to:
  /// **'次の操作へ'**
  String get projectDemoNext;

  /// No description provided for @projectDemoNotice.
  ///
  /// In ja, this message translates to:
  /// **'画面内のサンプルガイドです。実際の納品環境や動画には接続していません。'**
  String get projectDemoNotice;

  /// No description provided for @projectInfoMessageNotice.
  ///
  /// In ja, this message translates to:
  /// **'変更点やご不明点は、プロジェクトのメッセージからご相談ください。'**
  String get projectInfoMessageNotice;

  /// No description provided for @projectNextDeveloping.
  ///
  /// In ja, this message translates to:
  /// **'次の予定：10月16日 デモ確認'**
  String get projectNextDeveloping;

  /// No description provided for @projectNextInternalReview.
  ///
  /// In ja, this message translates to:
  /// **'次の予定：運営による内容確認'**
  String get projectNextInternalReview;

  /// No description provided for @projectNextAcceptance.
  ///
  /// In ja, this message translates to:
  /// **'次の予定：お客様による納品内容の確認'**
  String get projectNextAcceptance;

  /// No description provided for @projectNextRevision.
  ///
  /// In ja, this message translates to:
  /// **'次の予定：修正内容の確認と再提出'**
  String get projectNextRevision;

  /// No description provided for @projectNextCompleted.
  ///
  /// In ja, this message translates to:
  /// **'公開版の検収が完了しました'**
  String get projectNextCompleted;

  /// No description provided for @projectNextDefault.
  ///
  /// In ja, this message translates to:
  /// **'進行に合わせて次の予定をご案内します'**
  String get projectNextDefault;

  /// No description provided for @projectCheckFaqSearch.
  ///
  /// In ja, this message translates to:
  /// **'質問を入力し、関連する資料を検索できる'**
  String get projectCheckFaqSearch;

  /// No description provided for @projectCheckFaqSources.
  ///
  /// In ja, this message translates to:
  /// **'回答の根拠となる資料を確認できる'**
  String get projectCheckFaqSources;

  /// No description provided for @projectCheckGuide.
  ///
  /// In ja, this message translates to:
  /// **'操作説明を読み、利用方法を確認した'**
  String get projectCheckGuide;

  /// No description provided for @projectCheckSearch.
  ///
  /// In ja, this message translates to:
  /// **'問い合わせを登録・検索できる'**
  String get projectCheckSearch;

  /// No description provided for @projectCheckUpdate.
  ///
  /// In ja, this message translates to:
  /// **'担当者と対応状況を更新できる'**
  String get projectCheckUpdate;

  /// No description provided for @projectSubmissionDestination.
  ///
  /// In ja, this message translates to:
  /// **'{id} · 提出先：OPC 運営'**
  String projectSubmissionDestination(String id);

  /// No description provided for @projectAcceptConfirmBody.
  ///
  /// In ja, this message translates to:
  /// **'公開版 v{version}.0.0 の確認を完了します。\n\nこの操作は納品内容の検収記録です。支払いや精算は行いません。'**
  String projectAcceptConfirmBody(int version);

  /// No description provided for @projectCustomerVersion.
  ///
  /// In ja, this message translates to:
  /// **'お客様向け公開版 v{version}.0.0'**
  String projectCustomerVersion(int version);

  /// No description provided for @projectSubmittedVersion.
  ///
  /// In ja, this message translates to:
  /// **'提出バージョン {version}'**
  String projectSubmittedVersion(int version);

  /// No description provided for @projectFieldRequired.
  ///
  /// In ja, this message translates to:
  /// **'{label}を入力してください'**
  String projectFieldRequired(String label);

  /// No description provided for @projectTargetVersion.
  ///
  /// In ja, this message translates to:
  /// **'対象バージョン：{version}'**
  String projectTargetVersion(String version);

  /// No description provided for @projectDemoVersion.
  ///
  /// In ja, this message translates to:
  /// **'公開版 {version} · サンプルガイド'**
  String projectDemoVersion(String version);

  /// No description provided for @projectConfirmedScope.
  ///
  /// In ja, this message translates to:
  /// **'確認済みの対象範囲：バージョン {version}'**
  String projectConfirmedScope(int version);

  /// No description provided for @refTitle.
  ///
  /// In ja, this message translates to:
  /// **'参考資料'**
  String get refTitle;

  /// No description provided for @refPublishedVersion.
  ///
  /// In ja, this message translates to:
  /// **'{taskId} · 公開要件 v{version}.0'**
  String refPublishedVersion(String taskId, int version);

  /// No description provided for @refPublishedNotice.
  ///
  /// In ja, this message translates to:
  /// **'現在の公開要件に含まれる参考資料のみ表示しています。'**
  String get refPublishedNotice;

  /// No description provided for @refViewAll.
  ///
  /// In ja, this message translates to:
  /// **'すべて見る {count}'**
  String refViewAll(int count);

  /// No description provided for @refImages.
  ///
  /// In ja, this message translates to:
  /// **'画像 {count}'**
  String refImages(int count);

  /// No description provided for @refVideos.
  ///
  /// In ja, this message translates to:
  /// **'動画 {count}'**
  String refVideos(int count);

  /// No description provided for @refFiles.
  ///
  /// In ja, this message translates to:
  /// **'資料 {count}'**
  String refFiles(int count);

  /// No description provided for @refImageHint.
  ///
  /// In ja, this message translates to:
  /// **'画面イメージ'**
  String get refImageHint;

  /// No description provided for @refVideoHint.
  ///
  /// In ja, this message translates to:
  /// **'操作イメージ'**
  String get refVideoHint;

  /// No description provided for @refAttachments.
  ///
  /// In ja, this message translates to:
  /// **'添付ファイル'**
  String get refAttachments;

  /// No description provided for @refCount.
  ///
  /// In ja, this message translates to:
  /// **'{count} 件'**
  String refCount(int count);

  /// No description provided for @refOpenHint.
  ///
  /// In ja, this message translates to:
  /// **'タップして閲覧・再生。すべての資料を個別に保存できます。'**
  String get refOpenHint;

  /// No description provided for @refEmpty.
  ///
  /// In ja, this message translates to:
  /// **'公開されている参考資料はありません。'**
  String get refEmpty;

  /// No description provided for @refPreview.
  ///
  /// In ja, this message translates to:
  /// **'プレビュー'**
  String get refPreview;

  /// No description provided for @refDownload.
  ///
  /// In ja, this message translates to:
  /// **'原本をダウンロード'**
  String get refDownload;

  /// No description provided for @refImageDownload.
  ///
  /// In ja, this message translates to:
  /// **'画像をダウンロード'**
  String get refImageDownload;

  /// No description provided for @refVideoDownload.
  ///
  /// In ja, this message translates to:
  /// **'動画をダウンロード'**
  String get refVideoDownload;

  /// No description provided for @refDownloading.
  ///
  /// In ja, this message translates to:
  /// **'ダウンロード中 · {percent}%'**
  String refDownloading(int percent);

  /// No description provided for @refCancel.
  ///
  /// In ja, this message translates to:
  /// **'中止'**
  String get refCancel;

  /// No description provided for @refCancelled.
  ///
  /// In ja, this message translates to:
  /// **'ダウンロードを中止しました'**
  String get refCancelled;

  /// No description provided for @refDownloadFailed.
  ///
  /// In ja, this message translates to:
  /// **'ダウンロードに失敗しました'**
  String get refDownloadFailed;

  /// No description provided for @refRetry.
  ///
  /// In ja, this message translates to:
  /// **'再試行'**
  String get refRetry;

  /// No description provided for @refDownloaded.
  ///
  /// In ja, this message translates to:
  /// **'ダウンロード完了'**
  String get refDownloaded;

  /// No description provided for @refSavedInApp.
  ///
  /// In ja, this message translates to:
  /// **'アプリ内に保存しました。端末のファイルに保存するには「書き出す」を選んでください。'**
  String get refSavedInApp;

  /// No description provided for @refLocalSample.
  ///
  /// In ja, this message translates to:
  /// **'このアプリに同梱したサンプルの原本を保存します。'**
  String get refLocalSample;

  /// No description provided for @refOpen.
  ///
  /// In ja, this message translates to:
  /// **'開く'**
  String get refOpen;

  /// No description provided for @refExport.
  ///
  /// In ja, this message translates to:
  /// **'書き出す'**
  String get refExport;

  /// No description provided for @refActionFailed.
  ///
  /// In ja, this message translates to:
  /// **'ファイルを開くか書き出す操作を完了できませんでした。対応アプリや保存先を確認してください。'**
  String get refActionFailed;

  /// No description provided for @refAccessDenied.
  ///
  /// In ja, this message translates to:
  /// **'この資料へのアクセス権がありません。必要な場合は運営担当者にお問い合わせください。'**
  String get refAccessDenied;

  /// No description provided for @refScenarios.
  ///
  /// In ja, this message translates to:
  /// **'資料の表示状態'**
  String get refScenarios;

  /// No description provided for @refScenarioHelp.
  ///
  /// In ja, this message translates to:
  /// **'公開済みのサンプル資料で表示状態を確認できます。資料やアカウントの権限は変更しません。'**
  String get refScenarioHelp;

  /// No description provided for @refReady.
  ///
  /// In ja, this message translates to:
  /// **'プレビュー可能'**
  String get refReady;

  /// No description provided for @refPreparing.
  ///
  /// In ja, this message translates to:
  /// **'プレビューを準備中'**
  String get refPreparing;

  /// No description provided for @refPreviewFailed.
  ///
  /// In ja, this message translates to:
  /// **'プレビュー失敗'**
  String get refPreviewFailed;

  /// No description provided for @refUnsupported.
  ///
  /// In ja, this message translates to:
  /// **'プレビュー非対応'**
  String get refUnsupported;

  /// No description provided for @refDownloadFailureCase.
  ///
  /// In ja, this message translates to:
  /// **'ダウンロード失敗と再試行'**
  String get refDownloadFailureCase;

  /// No description provided for @refDownloadCancelCase.
  ///
  /// In ja, this message translates to:
  /// **'ダウンロード進捗と中止'**
  String get refDownloadCancelCase;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
