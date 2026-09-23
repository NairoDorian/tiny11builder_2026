<#
    Tiny11 Builder - Ultimate Edition : offline registry tweak catalog
    ==================================================================

    Every registry change the builders make to the *installed* image lives in
    this file, grouped by purpose. The builders load it with
    Get-TweakCatalog / Invoke-TweakCatalog (lib/tiny11utils.psm1),
    docs/TWEAKS.md is generated from it (scripts/update-generated.ps1) and the
    unit tests validate every entry, so this file is the single source of truth.

    Group fields
      Id          unique name, used with -SkipTweak
      Title       one-line description (shown in logs and docs)
      When        'Always', or the name of a build flag that must be $true
                  (preset keys such as RemoveAI, plus runtime flags such as
                  LowRam / DisableDriverUpdates / DisableWindowsUpdate).
                  Prefix with '!' to require the flag to be $false.
      Set         'HKLM\<hive>\<key>|<value name>|<type>|<data>'
                  (split on the first three '|', so data may contain '|';
                   an empty value name writes the key's default value)
      Delete      'HKLM\<hive>\<key>'  (whole key)  or  'HKLM\<hive>\<key>|<value name>'
      Services    '<service name>=<start type>'  (2 auto, 3 manual, 4 disabled;
                  skipped when the service does not exist in the image)
      FirstBoot   command lines appended to the image's SetupComplete.cmd
                  (run once as SYSTEM right after Windows Setup finishes)
      Notes       caveats, shown in docs/TWEAKS.md

    Hives: zSOFTWARE / zSYSTEM = HKLM\SOFTWARE / HKLM\SYSTEM of the image,
    zNTUSER = the Default user profile (every new account inherits it),
    zDEFAULT = the .DEFAULT profile used by the logon screen and services.
    Offline hives have no CurrentControlSet - always use ControlSet001.
#>
@{
    Groups = @(
        @{
            Id    = 'HardwareBypass'
            Title = 'Skip TPM / Secure Boot / CPU / RAM / storage checks and hide the "unsupported hardware" watermark'
            When  = 'Always'
            Set   = @(
                'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache|SV1|REG_DWORD|0'
                'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache|SV2|REG_DWORD|0'
                'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache|SV1|REG_DWORD|0'
                'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache|SV2|REG_DWORD|0'
                'HKLM\zSYSTEM\Setup\LabConfig|BypassCPUCheck|REG_DWORD|1'
                'HKLM\zSYSTEM\Setup\LabConfig|BypassRAMCheck|REG_DWORD|1'
                'HKLM\zSYSTEM\Setup\LabConfig|BypassSecureBootCheck|REG_DWORD|1'
                'HKLM\zSYSTEM\Setup\LabConfig|BypassStorageCheck|REG_DWORD|1'
                'HKLM\zSYSTEM\Setup\LabConfig|BypassTPMCheck|REG_DWORD|1'
                'HKLM\zSYSTEM\Setup\MoSetup|AllowUpgradesWithUnsupportedTPMOrCPU|REG_DWORD|1'
            )
        }
        @{
            Id    = 'SponsoredApps'
            Title = 'No silently installed / suggested / sponsored apps, clean Start pins'
            When  = 'DisableSponsoredApps'
            Set   = @(
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|ContentDeliveryAllowed|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|FeatureManagementEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|OemPreInstalledAppsEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|PreInstalledAppsEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|PreInstalledAppsEverEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SilentInstalledAppsEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SoftLandingEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContentEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-310093Enabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-338387Enabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-338388Enabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-338389Enabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-338393Enabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-353694Enabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-353696Enabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SystemPaneSuggestionsEnabled|REG_DWORD|0'
                'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start|ConfigureStartPins|REG_SZ|{"pinnedList": [{}]}'
                'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall|DisablePushToInstall|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\MRT|DontOfferThroughWUAU|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent|DisableCloudOptimizedContent|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent|DisableConsumerAccountStateContent|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent|DisableWindowsConsumerFeatures|REG_DWORD|1'
            )
            Delete = @(
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'
            )
        }
        @{
            Id    = 'Advertising'
            Title = 'Advertising ID, tailored experiences, Start/Settings/lock-screen suggestions and "finish setting up" nags off'
            When  = 'DisableAds'
            Set   = @(
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo|Enabled|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo|DisabledByGroupPolicy|REG_DWORD|1'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy|TailoredExperiencesWithDiagnosticDataEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|RotatingLockScreenEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|RotatingLockScreenOverlayEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|Start_IrisRecommendations|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|Start_AccountNotifications|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ShowSyncProviderNotifications|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement|ScoobeSystemSettingEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Mobility|OptedIn|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent|DisableWindowsSpotlightFeatures|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent|DisableSoftLanding|REG_DWORD|1'
            )
            Notes = 'DisableWindowsSpotlightFeatures also turns off Spotlight wallpapers on the lock screen and desktop.'
        }
        @{
            Id    = 'Telemetry'
            Title = 'Diagnostic data at the minimum, telemetry services and feedback prompts off'
            When  = 'DisableTelemetry'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection|DoNotShowFeedbackNotifications|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowDeviceNameInTelemetry|REG_DWORD|0'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection|AllowTelemetry|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppCompat|AITEnable|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppCompat|DisableInventory|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppCompat|DisableUAR|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\SQMClient\Windows|CEIPEnable|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\System|PublishUserActivities|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\System|UploadUserActivities|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\System|EnableActivityFeed|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting|Disabled|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization|DODownloadMode|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Siuf\Rules|NumberOfSIUFInPeriod|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy|HasAccepted|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Input\TIPC|Enabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\InputPersonalization|RestrictImplicitInkCollection|REG_DWORD|1'
                'HKLM\zNTUSER\Software\Microsoft\InputPersonalization|RestrictImplicitTextCollection|REG_DWORD|1'
                'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore|HarvestContacts|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings|AcceptedPrivacyPolicy|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|Start_TrackProgs|REG_DWORD|0'
            )
            Services = @(
                'DiagTrack=4'
                'dmwappushservice=4'
            )
            Notes = 'AllowTelemetry=0 is honoured as "Security" only on Enterprise/Education; Home/Pro clamp it to "Required". The DiagTrack service is disabled so nothing is uploaded either way.'
        }
        @{
            Id    = 'ThirdPartyTelemetry'
            Title = 'Opt out of telemetry in bundled runtimes (.NET CLI, PowerShell 7)'
            When  = 'DisableThirdPartyTelemetry'
            Set   = @(
                'HKLM\zSYSTEM\ControlSet001\Control\Session Manager\Environment|DOTNET_CLI_TELEMETRY_OPTOUT|REG_SZ|1'
                'HKLM\zSYSTEM\ControlSet001\Control\Session Manager\Environment|POWERSHELL_TELEMETRY_OPTOUT|REG_SZ|1'
            )
        }
        @{
            Id    = 'AI'
            Title = 'Copilot, Recall, Click to Do, Settings agent and in-app generative AI (Paint, Notepad, Edge) off'
            When  = 'RemoveAI'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot|TurnOffWindowsCopilot|REG_DWORD|1'
                'HKLM\zNTUSER\Software\Policies\Microsoft\Windows\WindowsCopilot|TurnOffWindowsCopilot|REG_DWORD|1'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ShowCopilotButton|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI|AllowRecallEnablement|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI|DisableAIDataAnalysis|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI|TurnOffSavingSnapshots|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI|DisableClickToDo|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI|DisableSettingsAgent|REG_DWORD|1'
                'HKLM\zNTUSER\Software\Policies\Microsoft\Windows\WindowsAI|DisableAIDataAnalysis|REG_DWORD|1'
                'HKLM\zNTUSER\Software\Policies\Microsoft\Windows\WindowsAI|DisableClickToDo|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppPrivacy|LetAppsAccessGenerativeAI|REG_DWORD|2'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppPrivacy|LetAppsAccessSystemAIModels|REG_DWORD|2'
                'HKLM\zSOFTWARE\Policies\WindowsNotepad|DisableAIFeatures|REG_DWORD|1'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint|DisableCocreator|REG_DWORD|1'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint|DisableGenerativeErase|REG_DWORD|1'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint|DisableGenerativeFill|REG_DWORD|1'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint|DisableImageCreator|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Edge|HubsSidebarEnabled|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Edge|CopilotPageContext|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Edge|Microsoft365CopilotChatIconEnabled|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Edge|ComposeInlineEnabled|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Edge|GenAILocalFoundationalModelSettings|REG_DWORD|1'
            )
            Services = @(
                'WSAIFabricSvc=4'
            )
            Notes = 'Recall/Click to Do policies only matter on Copilot+ PCs; they are harmless elsewhere. Edge policies apply only if Edge is later reinstalled.'
        }
        @{
            Id    = 'Search'
            Title = 'Start/taskbar search stays local: no Bing, web results, search highlights or Cortana'
            When  = 'DisableAds'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search|AllowCortana|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search|ConnectedSearchUseWeb|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search|DisableWebSearch|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search|EnableDynamicContentInWSB|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer|DisableSearchBoxSuggestions|REG_DWORD|1'
                'HKLM\zNTUSER\Software\Policies\Microsoft\Windows\Explorer|DisableSearchBoxSuggestions|REG_DWORD|1'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Search|BingSearchEnabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\SearchSettings|IsDynamicSearchBoxEnabled|REG_DWORD|0'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings|IsDynamicSearchBoxEnabled|REG_DWORD|0'
            )
        }
        @{
            Id    = 'Taskbar'
            Title = 'No Widgets / News, no Chat (Teams) button'
            When  = 'Always'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\Dsh|AllowNewsAndInterests|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Feeds|EnableFeeds|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat|ChatIcon|REG_DWORD|3'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|TaskbarMn|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|TaskbarDa|REG_DWORD|0'
            )
        }
        @{
            Id    = 'Oobe'
            Title = 'Offline/local-account OOBE, no privacy and personal-data-export pages, no first-logon animation'
            When  = 'Always'
            Set   = @(
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE|BypassNRO|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OOBE|DisablePrivacyExperience|REG_DWORD|1'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System|EnableFirstLogonAnimation|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\PersonalDataExport|PDEShown|REG_DWORD|2'
                'HKLM\zDEFAULT\Software\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\PersonalDataExport|PDEShown|REG_DWORD|2'
            )
        }
        @{
            Id    = 'Storage'
            Title = 'No reserved storage, no automatic BitLocker device encryption'
            When  = 'Always'
            Set   = @(
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager|ShippedWithReserves|REG_DWORD|0'
                'HKLM\zSYSTEM\ControlSet001\Control\BitLocker|PreventDeviceEncryption|REG_DWORD|1'
            )
            Notes = 'Manual BitLocker from Settings / manage-bde keeps working; only the silent auto-encryption on first sign-in is prevented.'
        }
        @{
            Id    = 'AppReinstall'
            Title = 'Stop Windows Update / OOBE from reinstalling Outlook, Dev Home and Teams'
            When  = 'RemoveAppx'
            Set   = @(
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate|workCompleted|REG_DWORD|1'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate|workCompleted|REG_DWORD|1'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate|workCompleted|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Teams|DisableInstallation|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail|PreventRun|REG_DWORD|1'
            )
            Delete = @(
                # The OOBE-time installers are triggered from this (different) key.
                'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
                'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'
            )
        }
        @{
            Id    = 'GameDvr'
            Title = 'Background game recording off (avoids "ms-gamingoverlay" pop-ups once Xbox Game Bar is removed)'
            When  = '!KeepXbox'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\GameDVR|AllowGameDVR|REG_DWORD|0'
                'HKLM\zNTUSER\System\GameConfigStore|GameDVR_Enabled|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\GameDVR|AppCaptureEnabled|REG_DWORD|0'
            )
        }
        @{
            Id    = 'EdgeRemoval'
            Title = 'Remove Edge uninstall entries, Active Setup stub and updater services; block Edge re-installation'
            When  = 'RemoveEdge'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\EdgeUpdate|DoNotUpdateToEdgeWithChromium|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\EdgeUpdate|InstallDefault|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\EdgeUpdate|UpdateDefault|REG_DWORD|0'
                'HKLM\zSOFTWARE\Microsoft\EdgeUpdate|DoNotUpdateToEdgeWithChromium|REG_DWORD|1'
                'HKLM\zSOFTWARE\WOW6432Node\Microsoft\EdgeUpdate|DoNotUpdateToEdgeWithChromium|REG_DWORD|1'
            )
            Delete = @(
                'HKLM\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
                'HKLM\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update'
                'HKLM\zSOFTWARE\Microsoft\Active Setup\Installed Components\{9459C573-B17A-45AE-9F64-1857B5D58CEE}'
                'HKLM\zSOFTWARE\WOW6432Node\Microsoft\Active Setup\Installed Components\{9459C573-B17A-45AE-9F64-1857B5D58CEE}'
                'HKLM\zSYSTEM\ControlSet001\Services\edgeupdate'
                'HKLM\zSYSTEM\ControlSet001\Services\edgeupdatem'
            )
            Notes = 'Edge WebView2 is kept unless the preset sets RemoveWebView: Widgets, Teams, Outlook and many third-party apps need it.'
        }
        @{
            Id    = 'OneDriveRemoval'
            Title = 'No OneDrive setup on first sign-in, no folder backup'
            When  = 'RemoveOneDrive'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive|DisableFileSyncNGSC|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive|KFMBlockOptIn|REG_DWORD|1'
            )
            Delete = @(
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Run|OneDriveSetup'
                'HKLM\zDEFAULT\Software\Microsoft\Windows\CurrentVersion\Run|OneDriveSetup'
            )
        }
        @{
            Id    = 'StoreRemoval'
            Title = 'Block the Microsoft Store (winget / App Installer keeps working)'
            When  = 'RemoveStore'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\WindowsStore|RemoveWindowsStore|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\WindowsStore|AutoDownload|REG_DWORD|2'
            )
        }
        @{
            Id    = 'DefenderOff'
            Title = 'Disable Microsoft Defender Antivirus services and hide the Windows Security page'
            When  = 'RemoveDefender'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender|DisableAntiSpyware|REG_DWORD|1'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer|SettingsPageVisibility|REG_SZ|hide:windowsdefender'
            )
            Services = @(
                'WinDefend=4'
                'WdNisSvc=4'
                'WdNisDrv=4'
                'WdFilter=4'
                'WdBoot=4'
                'Sense=4'
            )
            Notes = 'Leaves the machine without real-time antivirus. Intended for isolated VMs / labs only.'
        }
        @{
            Id    = 'DefenderCloud'
            Title = 'Keep Defender on, but stop cloud reporting (MAPS) and automatic sample submission'
            When  = 'DisableDefenderCloud'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Spynet|SpynetReporting|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Spynet|SubmitSamplesConsent|REG_DWORD|2'
            )
            Notes = 'Real-time protection stays on, but cloud-delivered protection (fast signature-less blocking) is lost.'
        }
        @{
            Id    = 'DefenderCpuLimit'
            Title = 'Cap Defender scheduled-scan CPU usage at 25 %'
            When  = 'TuneDefenderCpuLimit'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Scan|AvgCPULoadFactor|REG_DWORD|25'
            )
        }
        @{
            Id    = 'DriverUpdates'
            Title = 'Do not download device drivers from Windows Update'
            When  = 'DisableDriverUpdates'
            Set   = @(
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching|SearchOrderConfig|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate|ExcludeWUDriversInQualityUpdate|REG_DWORD|1'
            )
        }
        @{
            Id    = 'WindowsUpdateOff'
            Title = 'Disable Windows Update entirely (Core images: they cannot be serviced anyway)'
            When  = 'DisableWindowsUpdate'
            Set   = @(
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate|DoNotConnectToWindowsUpdateInternetLocations|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate|DisableWindowsUpdateAccess|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate|WUServer|REG_SZ|localhost'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate|WUStatusServer|REG_SZ|localhost'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate|UpdateServiceUrlAlternate|REG_SZ|localhost'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU|UseWUServer|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU|NoAutoUpdate|REG_DWORD|1'
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE|DisableOnline|REG_DWORD|1'
                # Superset of DefenderOff's value: Core always applies both groups and this one runs last.
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer|SettingsPageVisibility|REG_SZ|hide:windowsdefender;windowsupdate-action;windowsupdate-history;windowsupdate-options;windowsupdate-restartoptions;windowsupdate'
            )
            Delete = @(
                'HKLM\zSYSTEM\ControlSet001\Services\WaaSMedicSVC'
                'HKLM\zSYSTEM\ControlSet001\Services\UsoSvc'
            )
            Services = @(
                'wuauserv=4'
            )
            FirstBoot = @(
                'sc.exe config wuauserv start= disabled'
                'sc.exe stop wuauserv'
            )
            Notes = 'Deleting the UsoSvc/WaaSMedicSVC service keys is irreversible without reinstalling. Never use on a daily-driver PC.'
        }
        @{
            Id    = 'LowRam'
            Title = 'Low-RAM (1-2 GB) profile: fewer service hosts, no SysMain/Search indexing, no animations or background apps'
            When  = 'LowRam'
            Set   = @(
                'HKLM\zSYSTEM\ControlSet001\Control|SvcHostSplitThresholdInKB|REG_DWORD|3670016'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search|AllowCortana|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search|DisableWebSearch|REG_DWORD|1'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search|ConnectedSearchUseWeb|REG_DWORD|0'
                'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search|AllowSearchToUseLocation|REG_DWORD|0'
                'HKLM\zDEFAULT\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize|EnableTransparency|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize|EnableTransparency|REG_DWORD|0'
                'HKLM\zDEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects|VisualFXSetting|REG_DWORD|3'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects|VisualFXSetting|REG_DWORD|3'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|TaskbarAnimations|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|SearchboxTaskbarMode|REG_DWORD|0'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications|GlobalUserDisabled|REG_DWORD|1'
                'HKLM\zDEFAULT\Control Panel\Desktop\WindowMetrics|MinAnimate|REG_SZ|0'
                'HKLM\zNTUSER\Control Panel\Desktop\WindowMetrics|MinAnimate|REG_SZ|0'
            )
            Services = @(
                'SysMain=4'
                'WSearch=4'
            )
            Notes = 'Keeps Windows Update and Defender untouched (ported from bluecloud122). File search falls back to un-indexed search.'
        }
        @{
            Id    = 'DriverBlocklist'
            Title = 'Enforce the Microsoft vulnerable-driver blocklist'
            When  = 'EnableDriverBlocklist'
            Set   = @(
                'HKLM\zSYSTEM\ControlSet001\Control\CI\Config|VulnerableDriverBlocklistEnable|REG_DWORD|1'
            )
        }
        @{
            Id    = 'MouseAcceleration'
            Title = 'Disable "Enhance pointer precision" (raw 1:1 mouse movement)'
            When  = 'DisableMouseAcceleration'
            Set   = @(
                'HKLM\zNTUSER\Control Panel\Mouse|MouseSpeed|REG_SZ|0'
                'HKLM\zNTUSER\Control Panel\Mouse|MouseThreshold1|REG_SZ|0'
                'HKLM\zNTUSER\Control Panel\Mouse|MouseThreshold2|REG_SZ|0'
            )
        }
        @{
            Id    = 'FastShutdown'
            Title = 'Shorter shutdown timeouts: hung apps and services are closed after 2 s'
            When  = 'EnableFastShutdown'
            Set   = @(
                'HKLM\zSYSTEM\ControlSet001\Control|WaitToKillServiceTimeout|REG_SZ|2000'
                'HKLM\zNTUSER\Control Panel\Desktop|AutoEndTasks|REG_SZ|1'
                'HKLM\zNTUSER\Control Panel\Desktop|HungAppTimeout|REG_SZ|2000'
                'HKLM\zNTUSER\Control Panel\Desktop|WaitToKillAppTimeout|REG_SZ|2000'
            )
            Notes = 'Apps with unsaved work are closed without asking at shutdown.'
        }
        @{
            Id    = 'UtcClock'
            Title = 'Hardware clock in UTC (for dual-boot with Linux)'
            When  = 'EnableUtcClock'
            Set   = @(
                'HKLM\zSYSTEM\ControlSet001\Control\TimeZoneInformation|RealTimeIsUniversal|REG_DWORD|1'
            )
            Notes = 'Only useful when another OS shares the RTC; otherwise leave off.'
        }
        @{
            Id    = 'ZoneInformation'
            Title = 'Do not tag downloads with Mark-of-the-Web'
            When  = 'DisableZoneInformation'
            Set   = @(
                'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments|SaveZoneInformation|REG_DWORD|1'
                'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments|SaveZoneInformation|REG_DWORD|1'
            )
            Notes = 'Security trade-off: SmartScreen and Office Protected View rely on Mark-of-the-Web. Off in the Default preset.'
        }
        @{
            Id    = 'FirewallTelemetry'
            Title = 'Outbound firewall rules blocking the compatibility-telemetry binaries'
            When  = 'BlockFirewallTelemetry'
            Set   = @(
                'HKLM\zSYSTEM\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules|Tiny11-Block-CompatTelRunner|REG_SZ|v2.10|Action=Block|Active=TRUE|Dir=Out|App=%SystemRoot%\system32\CompatTelRunner.exe|Name=Tiny11: block CompatTelRunner|'
                'HKLM\zSYSTEM\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules|Tiny11-Block-DeviceCensus|REG_SZ|v2.10|Action=Block|Active=TRUE|Dir=Out|App=%SystemRoot%\system32\DeviceCensus.exe|Name=Tiny11: block DeviceCensus|'
            )
        }
        @{
            Id        = 'UltimatePerformance'
            Title     = 'Activate the Ultimate Performance power plan on first boot'
            When      = 'EnableUltimatePerformance'
            FirstBoot = @(
                'powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 11111111-2222-3333-4444-555555555555'
                'powercfg.exe -setactive 11111111-2222-3333-4444-555555555555'
            )
            Notes = 'Higher idle power draw; not recommended on laptops running on battery.'
        }
    )
}
