{-# LANGUAGE RecursiveDo #-}
{-|
Module      : Gonimo.Client.UI.Dialogs.Invite
Description : Dialogs for showing invitation code and sending invitations.
Copyright   : (c) Robert Klotzner, 2018
-}
module Gonimo.Client.UI.Dialogs.Invite where

import           Data.Map.Strict                      (Map)
import qualified Data.Text                            as T
import           Data.Time                            (diffUTCTime,
                                                       getCurrentTime)
import           Reflex.Dom.Core
import           Reflex.Dom.MDC.Dialog                (Dialog)
import qualified Reflex.Dom.MDC.Dialog                as Dialog
import           Reflex.Network


import qualified Gonimo.Client.Account                as Account
import qualified Gonimo.Client.Device                 as Device
import qualified Gonimo.Client.Family                 as Family
import           Gonimo.Client.Model                  (IsConfig)
import           Gonimo.Client.Prelude
import           Gonimo.Client.Reflex.Dom
import qualified Gonimo.Client.Settings               as Settings
import           Gonimo.Client.UI.Dialogs.Invite.I18N
import           Gonimo.I18N                          (i18n)
import qualified Gonimo.SocketAPI.Types               as API



type HasModelConfig c t = (IsConfig c t, Account.HasConfig c, Device.HasConfig c)

type HasModel model = (Account.HasAccount model, Device.HasDevice model)


data Config t
  = Config { _onOpen  :: Event t ()
           , _onClose :: Event t ()
           }

ui :: forall model mConf m t. (HasModelConfig mConf t, HasModel model, GonimoM model t m)
  => Config t -> m (mConf t)
ui conf = mdo
  loc <- view Settings.locale
  model <- ask
  remTime <- showRemainingTime model dialog
  primaryBarAnimAttrs <- makeAnimationAttrs dialog $ "class" =: "mdc-linear-progress__bar mdc-linear-progress__primary-bar"
  progressAnimAttrs   <- makeAnimationAttrs dialog $ "class" =: "mdc-linear-progress__bar-inner"
  codeFieldAnimAttrs  <- makeAnimationAttrs dialog $ "class" =: "code-field"
  codeTimeAnimAttrs   <- makeAnimationAttrs dialog $ "class" =: "code-time"
  dialog <- Dialog.make
    $ Dialog.ConfigBase
    { Dialog._onOpen    = _onOpen conf
    , Dialog._onClose   = _onClose conf
    , Dialog._onDestroy = never
    , Dialog._header    = Dialog.HeaderHeading $ liftA2 i18n loc (pure Invitation_Code)
    , Dialog._body      = do
        elClass "div" "code-txt" $ do
          elDynAttr "h2" codeFieldAnimAttrs $ dynText (showCode model)
          elAttr "div" ("role" =: "progressbar" <> "class" =: "mdc-linear-progress") $ do
            elDynAttr "div" primaryBarAnimAttrs $ do
              elDynAttr "span" progressAnimAttrs blank
          elAttr "p" ("class" =: "mdc-text-field-helper-text--persistent" <> "aria-hidden" =: "true") $ do
            elAttr "i" ("class" =: "material-icons" <> "aria-hidden" =: "true") $ text "schedule"
            elDynAttr "span" codeTimeAnimAttrs $ dynText remTime
          elClass "div" "mdc-menu-anchor" $ do
            elAttr "button" ("type" =: "button" <> "class" =: "mdc-button mdc-button--flat btn share-btn") $ do
              elAttr "i" ("class" =: "material-icons" <> "aria-hidden" =: "true") $ text "share"
              text "Teilen"
            elAttr "div" ("class" =: "mdc-simple-menu" <> "tabindex" =: "-1") $ do
              elAttr "ul" ("class" =: "mdc-simple-menu__items mdc-list" <> "role" =: "menu" <> "aria-hidden" =: "true") $ do
                elAttr "li" ("class" =: "mdc-list-item" <> "role" =: "menuitem" <> "tabindex" =: "0") $ do
                  elClass "i" "material-icons" $ text "mail"
                  text "Mail"
                elAttr "li" ("class" =: "mdc-list-item" <> "role" =: "menuitem" <> "tabindex" =: "0") $ do
                  elClass "i" "material-icons" $ text "content_copy"
                  text "Kopieren"
        el "br" blank
        Dialog.separator
        el "br" blank
    , Dialog._footer    = Dialog.cancelOnlyFooter $ liftA2 i18n loc (pure Cancel)
    }
  controller dialog

makeAnimationAttrs :: forall model m t. (HasModel model, GonimoM model t m)
  => Dialog t () -> Map Text Text -> m (Dynamic t (Map Text Text))
makeAnimationAttrs dialog staticAttrs = do
    fam <- view Device.selectedFamily
    let
      isOpen = dialog ^. Dialog.isOpen

      onAnimationEvents = updated $ isJust <$> fam ^. Family.activeInvitationCode

      onAnimationStart = gate (current isOpen) . ffilter_ id $ onAnimationEvents

      onAnimationEnd = leftmost [ ffilter_ not onAnimationEvents
                                , dialog ^. Dialog.onClosed
                                ]

    -- Small delay so the animation starts reliably.
    -- onAnimationStart <- delay 1 $ ffilter_ id onAnimationEvents

    foldDyn id staticAttrs $ leftmost [ addAnimAttrs <$ onAnimationStart
                                      , removeAnimAttrs <$ onAnimationEnd
                                      ]
  where
    removeAnimAttrs = (at "style" .~ Nothing) . removeClassAttr "anim"

    addAnimAttrs = addAnimDuration . addClassAttr "anim"

    addAnimDuration = at "style" .~ Just ("animation-duration: " <> animDurationText <> ";")

    animDurationText = (T.pack . show) Family.codeTimeout <> "s"

showRemainingTime :: ( Reflex t, Device.HasDevice model, Settings.HasSettings model
                     , MonadIO m, PerformEvent t m, MonadIO (Performable m), NotReady t m, Adjustable t m, PostBuild t m
                     , TriggerEvent t m, MonadFix m, MonadHold t m
                     )
                  => model t -> Dialog t () -> m (Dynamic t Text)
showRemainingTime model dialog = do
    let
      fam = model ^. Device.selectedFamily
      isOpen = dialog ^. Dialog.isOpen

      validUntil = current $ fam ^. Family.codeValidUntil

    -- Get a tick event that only happens if the dialog is shown:
    tickEv <- switchHold never <=< networkView $ getTicker <$> isOpen
    let
      ticker = tag validUntil $ leftmost [ () <$ tickEv
                                         , dialog ^. Dialog.onOpened
                                         ]

    onRem <- performEvent $ calcRemTime <$> ticker
    holdDyn "-:--" onRem
  where
    calcRemTime Nothing = pure "-:--"
    calcRemTime (Just deadLine) = showSeconds . diffUTCTime deadLine <$> liftIO getCurrentTime
    showSeconds = T.pack . ("0:" ++) . fillWithZeros . takeWhile (/= '.') . show

    fillWithZeros (x:[]) = '0' : x : []
    fillWithZeros xs     = xs

    getTicker False = pure never
    getTicker True = do
      now <- liftIO getCurrentTime
      postBuild <- getPostBuild
      tickLossyFrom 1 now postBuild

showCode :: (Reflex t, Device.HasDevice model, Settings.HasSettings model)
  => model t -> Dynamic t Text
showCode model = do
  let loc = model ^. Settings.locale
  let fam = model ^. Device.selectedFamily

  mCode <- fam ^. Family.activeInvitationCode
  loadingStr <- liftA2 i18n loc (pure Loading)
  pure $ maybe loadingStr API.codeToText $ mCode

-- | "Business logic" of this screen.
--
--   Created a modelconfig based on the current state of affairs.
controller :: forall model mConf m t. (HasModelConfig mConf t, HasModel model, GonimoM model t m)
  => Dialog.Dialog t () -> m (mConf t)
controller dialog = do
  model <- ask
  let
    fam = model ^. Device.selectedFamily

    isOpen = dialog ^. Dialog.isOpen
    onOpened = dialog ^. Dialog.onOpened

  onCreateFamily     <- Account.ifFamiliesEmpty model onOpened
  onCreateInvitation <- Family.ifNoActiveInvitation fam onOpened
  onCreateCodeStart  <- Family.withInvitation fam onOpened

  let
    onCodeInvalid = ffilter_ id
                    . fmap isNothing . updated
                    $ fam ^. Family.activeInvitationCode

  onCreateCodeReload <- Family.withInvitation fam
                        . ffilter_ id . attachWith (&&) (current isOpen)
                        $ leftmost [ False <$  dialog ^. Dialog.onClosed -- Necessary so we won't create a new code on closing.
                                   , True <$ onCodeInvalid
                                   ]

  let
    famConf = mempty & Family.onCreateInvitation .~ onCreateInvitation
                     & Family.onCreateCode .~ leftmost [ onCreateCodeStart
                                                       , onCreateCodeReload
                                                       ]
                     & Family.onClearCode .~ dialog ^. Dialog.onClosed
  pure $ mempty & Account.onCreateFamily .~ onCreateFamily
                & Device.familyConfig .~ famConf

-- Auto generated lenses ..

-- Lenses for Config t:

onOpen :: Lens' (Config t) (Event t ())
onOpen f config' = (\onOpen' -> config' { _onOpen = onOpen' }) <$> f (_onOpen config')

onClose :: Lens' (Config t) (Event t ())
onClose f config' = (\onClose' -> config' { _onClose = onClose' }) <$> f (_onClose config')


