-- -*-haskell-*-
--  GIMP Toolkit (GTK) Pango text layout functions
--
--  Author : Axel Simon
--
--  Created: 8 Feburary 2003
--
--  Version $Revision: 1.1 $ from $Date: 2005/08/20 13:25:19 $
--
--  Copyright (C) 1999-2005 Axel Simon
--
--  This library is free software; you can redistribute it and/or
--  modify it under the terms of the GNU Lesser General Public
--  License as published by the Free Software Foundation; either
--  version 2.1 of the License, or (at your option) any later version.
--
--  This library is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
--  Lesser General Public License for more details.
--
-- Not bound:
--
-- Functions that are missing:
--   pango_layout_set_attributes, pango_layout_get_attributes,
--   pango_layout_set_font_description, pango_layout_set_tabs,
--   pango_layout_get_tabs, pango_layout_get_log_attrs, 
--   pango_layout_iter_get_run
--
-- The following functions cannot be bound easily due to Unicode\/UTF8 issues:
--   pango_layout_xy_to_index, pango_layout_index_to_pos,
--   pango_layout_get_cursor_pos, pango_layout_move_cursor_visually,
--   pango_layout_iter_get_index, pango_layout_line_index_to_x,
--   pango_layout_line_x_to_index, pango_layout_line_get_x_ranges
--
-- These functions are not bound, because they're too easy:
--   pango_layout_get_size, pango_layout_get_pixel_size,
--   pango_layout_get_line 
--
-- |
-- Maintainer  : gtk2hs-users@lists.sourceforge.net
-- Stability   : provisional
-- Portability : portable (depends on GHC)
--
-- Functions to run the rendering pipeline.
--
-- * The objects in this model contain a rendered paragraph of text. This
--   interface is the easiest way to render text into a
--   'Graphics.UI.Gtk.Gdk.DrawWindow'.
--
module Graphics.UI.Gtk.Pango.Layout (
  PangoUnit,
  PangoRectangle(..),
  PangoLayout,
  layoutEmpty,
  layoutCopy,
  layoutGetContext,
  layoutContextChanged,
  layoutSetText,
  layoutGetText,
  layoutSetMarkup,
  escapeMarkup,
  layoutSetMarkupWithAccel,
  layoutSetWidth,
  layoutGetWidth,
  LayoutWrapMode(..),
  layoutSetWrap,
  layoutGetWrap,
#if GTK_CHECK_VERSION(2,4,0)
  EllipsizeMode(..),
  layoutSetEllipsize,
  layoutGetEllipsize,
#endif
  layoutSetIndent,
  layoutGetIndent,
  layoutSetSpacing,
  layoutGetSpacing,
  layoutSetJustify,
  layoutGetJustify,
  layoutSetAutoDir,
  layoutGetAutoDir,
  LayoutAlignment(..),
  layoutSetAlignment,
  layoutGetAlignment,
  layoutSetSingleParagraphMode,
  layoutGetSingleParagraphMode,
  layoutXYToIndex,
  layoutIndexToPos,
  layoutGetCursorPos,
  CursorPos(..),
  layoutMoveCursorVisually,
  layoutGetExtents,
  layoutGetPixelExtents,
  layoutGetLineCount,
  layoutGetLine,
  layoutGetLines,
  LayoutIter,
  layoutGetIter,
  layoutIterNextItem,
  layoutIterNextChar,
  layoutIterNextCluster,
  layoutIterNextLine,
  layoutIterAtLastLine,
  layoutIterGetIndex,
  layoutIterGetBaseline,
  layoutIterGetLine,
  layoutIterGetCharExtents,
  layoutIterGetClusterExtents,
  layoutIterGetRunExtents,
  layoutIterGetLineYRange,
  layoutIterGetLineExtents,
  LayoutLine,
  layoutLineGetExtents,
  layoutLineGetPixelExtents,
  layoutLineIndexToX,
  layoutLineXToIndex
  ) where

import Monad    (liftM)
import Char     (ord, chr)

import System.Glib.FFI
import System.Glib.UTFString
import System.Glib.GList                (readGSList)
import System.Glib.GObject              (makeNewGObject, objectRef)
{#import Graphics.UI.Gtk.Types#}
import Graphics.UI.Gtk.Pango.Markup	(Markup)
import Graphics.UI.Gtk.General.Enums
import Graphics.UI.Gtk.General.Structs	(Rectangle, pangoScale)
{#import Graphics.UI.Gtk.Pango.Types#}
import Graphics.UI.Gtk.Pango.Rendering  -- for haddock
import Data.IORef
import Control.Exception ( throwIO,
			   Exception(ArrayException),
			   ArrayException(IndexOutOfBounds) )

{# context lib="pango" prefix="pango" #}

-- | Create an empty 'Layout'.
--
layoutEmpty :: PangoContext -> IO PangoLayout
layoutEmpty pc = do
  pl <- makeNewGObject mkPangoLayoutRaw
    ({#call unsafe layout_new#} (toPangoContext pc))
  ps <- makeNewPangoString ""
  psRef <- newIORef ps
  return (PangoLayout psRef pl)

-- | Create a copy of the 'Layout'.
--
layoutCopy :: PangoLayout -> IO PangoLayout
layoutCopy (PangoLayout uc pl) = do
  pl <- makeNewGObject mkPangoLayoutRaw
    ({#call unsafe layout_copy#} pl)
  return (PangoLayout uc pl)

-- | Retrieves the 'PangoContext' from this layout.
--
layoutGetContext :: PangoLayout -> IO PangoContext
layoutGetContext (PangoLayout _ pl) = do
  pcPtr <- {#call unsafe layout_get_context#} pl
  objectRef pcPtr
  pc <- makeNewGObject mkPangoContext (return pcPtr)
  return pc
   

-- | Signal a 'Context' change.
--
-- * Forces recomputation of any state in the 'PangoLayout' that
--   might depend on the layout's context. This function should
--   be called if you make changes to the context subsequent
--   to creating the layout.
--
layoutContextChanged :: PangoLayout -> IO ()
layoutContextChanged (PangoLayout _ pl) =
  {#call unsafe layout_context_changed#} pl

-- | Set the string in the layout.
--
layoutSetText :: PangoLayout -> String -> IO ()
layoutSetText (PangoLayout psRef pl) txt = do
  withUTFStringLen txt $ \(strPtr,len) ->
    {#call unsafe layout_set_text#} pl strPtr (fromIntegral len)
  ps <- makeNewPangoString txt
  writeIORef psRef ps

-- | Retrieve the string in the layout.
--
layoutGetText :: PangoLayout -> IO String
layoutGetText (PangoLayout _ pl) =
  {#call unsafe layout_get_text#} pl >>= peekUTFString

-- | Set the string in the layout.
--
-- * The string may include 'Markup'. To print markup characters like
--   "<", or "-", apply 'escapeMarkup' on it first. The function returns
--   the text that is actually shown.
--
layoutSetMarkup :: PangoLayout -> Markup -> IO String
layoutSetMarkup pl@(PangoLayout psRef plr) txt = do
  withUTFStringLen txt $ \(strPtr,len) ->
    {#call unsafe layout_set_markup#} plr strPtr (fromIntegral len)
  txt' <- layoutGetText pl
  ps <- makeNewPangoString txt'
  writeIORef psRef ps
  return txt'

-- | Escape markup characters.
--
-- * Used to display characters that normally denote markup. Note that this
--   function is strict in that it forces all characters in the input string
--   as soon as a single output character is requested.
--
escapeMarkup :: String -> String
escapeMarkup str = unsafePerformIO $ withUTFStringLen str $ \(strPtr,l) -> do
  resPtr <- {#call unsafe g_markup_escape_text#} strPtr (fromIntegral l)
  res <- peekUTFString resPtr
  {#call unsafe g_free#} (castPtr resPtr)
  return res

-- | Set the string in the layout.
--
-- * The string may include 'Markup'. Furthermore, any underscore
--   character indicates that the next character should be
--   marked as accelerator (i.e. underlined). A literal underscore character
--   can be produced by placing it twice in the string.
--
-- * The character which follows the underscore is
--   returned so it can be used to add the actual keyboard shortcut.
--   The second element is the string after parsing.
--
layoutSetMarkupWithAccel :: PangoLayout -> Markup -> IO (Char, String)
layoutSetMarkupWithAccel pl@(PangoLayout psRef plr) txt = do
  modif <- alloca $ \chrPtr -> 
    withUTFStringLen txt $ \(strPtr,len) -> do
      {#call unsafe layout_set_markup_with_accel#} plr strPtr
        (fromIntegral len) (fromIntegral (ord '_')) chrPtr
      liftM (chr.fromIntegral) $ peek chrPtr
  txt' <- layoutGetText pl
  ps <- makeNewPangoString txt'
  writeIORef psRef ps
  return (modif, txt')

-- there are a couple of functions missing here

-- | Set the width of this paragraph.
--
-- * Sets the width to which the lines of the 'PangoLayout'
--   should be wrapped.
--
-- * Pass in @Nothing@ to indicate that no wrapping is to be performed.
--
layoutSetWidth :: PangoLayout -> Maybe PangoUnit -> IO ()
layoutSetWidth (PangoLayout _ pl) Nothing =
  {#call unsafe layout_set_width#} pl (-1)
layoutSetWidth (PangoLayout _ pl) (Just pu) =
  {#call unsafe layout_set_width#} pl (puToInt pu)

-- | Gets the width of this paragraph.
--
-- * Gets the width to which the lines of the 'PangoLayout'
--   should be wrapped.
--
-- * Returns is the current width, or @Nothing@ to indicate that
--   no wrapping is performed.
--
layoutGetWidth :: PangoLayout -> IO (Maybe PangoUnit)
layoutGetWidth (PangoLayout _ pl) = do
  w <- {#call unsafe layout_get_width#} pl
  return (if w==(-1) then Nothing else Just (intToPu w))

-- | Enumerates how a line can be wrapped.
--
-- [@WrapWholeWords@] Breaks lines only between words.
--
-- * This variant does not guarantee that the requested width is not
--   exceeded. A word that is longer than the paragraph width is not
--   split.
--
-- [@WrapAnywhere@] Break lines anywhere.
--
-- [@WrapPartialWords@] Wrap within a word if it is the only one on
-- this line.
--
-- * This option acts like 'WrapWholeWords' but will split
--   a word if it is the only one on this line and it exceeds the
--   specified width.
--
{#enum PangoWrapMode as LayoutWrapMode 
  {underscoreToCase,
  PANGO_WRAP_WORD as WrapWholeWords,
  PANGO_WRAP_CHAR as WrapAnywhere,
  PANGO_WRAP_WORD_CHAR as WrapPartialWords}#}

-- | Set how this paragraph is wrapped.
--
-- * Sets the wrap style; the wrap style only has an effect if a width
--   is set on the layout with 'layoutSetWidth'. To turn off
--   wrapping, call 'layoutSetWidth' with @Nothing@.
--
layoutSetWrap :: PangoLayout -> LayoutWrapMode -> IO ()
layoutSetWrap (PangoLayout _ pl) wm =
  {#call unsafe layout_set_wrap#} pl ((fromIntegral.fromEnum) wm)


-- | Get the wrap mode for the layout.
--
layoutGetWrap :: PangoLayout -> IO LayoutWrapMode
layoutGetWrap (PangoLayout _ pl) = liftM (toEnum.fromIntegral) $
  {#call unsafe layout_get_wrap#} pl

#if GTK_CHECK_VERSION(1,4,0)
-- | Ellipsize a text if it is too long.
--
-- * The 'EllipsizeMode' type describes what sort of (if any) ellipsization
--   should be applied to a line of text. In the ellipsization process
--   characters are removed from the text in order to make it fit to a given
--   width and replaced with an ellipsis.
--
{#enum PangoEllipsizeMode as EllipsizeMode
  {underscoreToCase,
  PANGO_ELLIPSIZE_NONE as EllipsizeNone,
  PANGO_ELLIPSIZE_START as EllipsizeStart,
  PANGO_ELLIPSIZE_MIDDLE as EllipsizeMiddle,
  PANGO_ELLIPSIZE_END as EllipsizeEnd } #}

-- | Set how long lines should be abbreviated.
--
layoutSetEllipsize :: PangoLayout -> EllipsizeMode -> IO ()
layoutSetEllipsize (PangoLayout _ pl) em =
  {#call unsafe layout_set_ellipsize#} pl ((fromIntegral.fromEnum) em)

-- | Get the ellipsize mode for this layout.
--
layoutGetEllipsize :: PangoLayout -> IO EllipsizeMode
layoutGetEllipsize (PangoLayout _ pl) = liftM (toEnum.fromIntegral) $
  {#call unsafe layout_get_ellipsize#} pl

#endif

-- | Set the indentation of this paragraph.
--
-- * Sets the amount by which the first line should
--   be indented. A negative value will produce a hanging indent, that is,
--   all subsequent lines will be indented while the first line has full
--   width.
--
layoutSetIndent :: PangoLayout -> PangoUnit -> IO ()
layoutSetIndent (PangoLayout _ pl) indent =
  {#call unsafe layout_set_indent#} pl (puToInt indent)

-- | Gets the indentation of this paragraph.
--
-- * Gets the amount by which the first line or the rest of the paragraph
--   is indented.
--
layoutGetIndent :: PangoLayout -> IO PangoUnit
layoutGetIndent (PangoLayout _ pl) = 
  liftM intToPu $ {#call unsafe layout_get_indent#} pl


-- | Set the spacing between lines of this paragraph.
--
layoutSetSpacing :: PangoLayout -> PangoUnit -> IO ()
layoutSetSpacing (PangoLayout _ pl) spacing =
  {#call unsafe layout_set_spacing#} pl (puToInt spacing)

-- | Gets the spacing between the lines.
--
layoutGetSpacing :: PangoLayout -> IO PangoUnit
layoutGetSpacing (PangoLayout _ pl) = 
  liftM intToPu $ {#call unsafe layout_get_spacing#} pl

-- | Set if text should be streched to fit width.
--
-- * Sets whether or not each complete line should be stretched to
--   fill the entire width of the layout. This stretching is typically
--   done by adding whitespace, but for some scripts (such as Arabic),
--   the justification is done by extending the characters.
--
-- * Note that  as of Pango 1.4, this functionality is not yet implemented.
--
layoutSetJustify :: PangoLayout -> Bool -> IO ()
layoutSetJustify (PangoLayout _ pl) j = 
  {#call unsafe layout_set_justify#} pl (fromBool j)

-- | Retrieve the justification flag.
--
-- * See 'layoutSetJustify'.
--
layoutGetJustify :: PangoLayout -> IO Bool
layoutGetJustify (PangoLayout _ pl) = 
  liftM toBool $ {#call unsafe layout_get_justify#} pl

-- | Set if the base text direction should be overridden.
--
-- * Sets whether to calculate the bidirectional base direction for the
--   layout according to the contents of the layout; when this flag is on
--   (the default), then paragraphs in layout that begin with strong
--   right-to-left characters (Arabic and Hebrew principally), will have
--   right-to-left layout, paragraphs with letters from other scripts will
--   have left-to-right layout. Paragraphs with only neutral characters get
--   their direction from the surrounding paragraphs.
--
-- * When @False@, the choice between left-to-right and right-to-left
--   layout is done by according to the base direction of the layout's
--   'PangoContext'. (See 'contextSetBaseDir').
--
-- * When the auto-computed direction or a paragraph differs from the base
--   direction of the context, then the interpretation of
--   'AlignLeft' and 'AlignRight' are swapped.
--
layoutSetAutoDir :: PangoLayout -> Bool -> IO ()
layoutSetAutoDir (PangoLayout _ pl) j = 
  {#call unsafe layout_set_auto_dir#} pl (fromBool j)

-- | Retrieve the auto direction flag.
--
-- * See 'layoutSetAutoDir'.
--
layoutGetAutoDir :: PangoLayout -> IO Bool
layoutGetAutoDir (PangoLayout _ pl) = 
  liftM toBool $ {#call unsafe layout_get_auto_dir#} pl


-- | Enumerate to which side incomplete lines are flushed.
--
{#enum PangoAlignment as LayoutAlignment {underscoreToCase}#}

-- | Set how this paragraph is aligned.
--
-- * Sets the alignment for the layout (how partial lines are
--   positioned within the horizontal space available.)
--
layoutSetAlignment :: PangoLayout -> LayoutAlignment -> IO ()
layoutSetAlignment (PangoLayout _ pl) am =
  {#call unsafe layout_set_alignment#} pl ((fromIntegral.fromEnum) am)


-- | Get the alignment for the layout.
--
layoutGetAlignment :: PangoLayout -> IO LayoutAlignment
layoutGetAlignment (PangoLayout _ pl) = liftM (toEnum.fromIntegral) $
  {#call unsafe layout_get_alignment#} pl

-- functions are missing here

-- | Honor newlines or not.
--
-- * If @honor@ is @True@, do not treat newlines and
--   similar characters as paragraph separators; instead, keep all text in
--   a single paragraph, and display a glyph for paragraph separator
--   characters. Used when you want to allow editing of newlines on a
--   single text line.
--
layoutSetSingleParagraphMode :: PangoLayout -> Bool -> IO ()
layoutSetSingleParagraphMode (PangoLayout _ pl) honor = 
  {#call unsafe layout_set_single_paragraph_mode#} pl (fromBool honor)

-- | Retrieve if newlines are honored.
--
-- * See 'layoutSetSingleParagraphMode'.
--
layoutGetSingleParagraphMode :: PangoLayout -> IO Bool
layoutGetSingleParagraphMode (PangoLayout _ pl) = 
  liftM toBool $ {#call unsafe layout_get_single_paragraph_mode#} pl

-- a function is missing here

-- | Converts a device unit to a character index.
--
-- * Converts from @x@ and @y@ position within a layout to the index of
--   the closest character. If the @y@ position is not inside the layout,
--   the closest position is chosen (the position will be clamped inside
--   the layout). If the @x@ position is not within the layout, then the
--   start or the end of the line is chosen. If either the @x@ or @y@
--   positions were not inside the layout, then the function returns @False@;
--   on an exact hit, it returns @True@.
--
-- * The function returns the flag for the exact hit and the index into
--   the string. The third value is zero if the character corresponds to
--   one grapheme. If the grapheme is the result of a cluster, this value
--   may be greater than one, indicating where in the grapheme the position
--   lies. Zero represents the trailing edge on the grapheme.
--
layoutXYToIndex :: PangoLayout -> PangoUnit -- ^ the @x@ position
		-> PangoUnit -- ^ the @y@ position
		-> IO (Bool, Int, Int)
layoutXYToIndex (PangoLayout psRef pl) x y = 
  alloca $ \idxPtr -> alloca $ \trailPtr -> do
    res <- {#call unsafe layout_xy_to_index#} pl (puToInt x) (puToInt y)
      idxPtr trailPtr
    idx <- peek idxPtr
    trail <- peek trailPtr
    (PangoString uc _ _) <- readIORef psRef
    return (toBool res,
	    ofsFromUTF (fromIntegral idx) uc,
	    ofsFromUTF (fromIntegral trail) uc)

-- | Return the rectangle of the glyph at the given index.
--
-- * Converts from an index within a 'PangoLayout' to the onscreen position
--   corresponding to the grapheme at that index, which is represented as
--   rectangle. Note that, given a @PangoRectangle x y width height@, @x@
--   is always the leading edge of the grapheme and @x + width@ the
--   trailing edge of the grapheme. If the directionality of the grapheme
--   is right-to-left, then @width@ will be negative.
--
layoutIndexToPos :: PangoLayout -> Int -> IO PangoRectangle
layoutIndexToPos (PangoLayout psRef plr) pos = do
  (PangoString uc _ _) <- readIORef psRef
  alloca $ \rectPtr -> do
    {#call unsafe layout_index_to_pos#} plr (fromIntegral (ofsToUTF pos uc))
					    (castPtr rectPtr)
    liftM fromRect $ peek rectPtr

-- | Return a cursor position.
--
-- * Given an index within a layout, determines the positions that of the
--   strong and weak cursors if the insertion point is at that index.
--   The position of each cursor is stored as a zero-width rectangle.
--   The strong cursor location is the location where characters of the
--   directionality equal to the base direction of the layout are inserted.
--   The weak cursor location is the location where characters of the
--   directionality opposite to the base direction of the layout are
--   inserted. The first element of the typle is the strong position,
--   the second the weak.
--
layoutGetCursorPos :: PangoLayout -> Int ->
		      IO (PangoRectangle, PangoRectangle)
layoutGetCursorPos (PangoLayout psRef plr) pos = do
  (PangoString uc _ _) <- readIORef psRef
  alloca $ \strongPtr -> alloca $ \weakPtr -> do
    {#call unsafe layout_get_cursor_pos#} plr (fromIntegral (ofsToUTF pos uc))
      (castPtr strongPtr) (castPtr weakPtr)
    strong <- peek strongPtr
    weak <- peek weakPtr
    return (fromRect strong, fromRect weak)


-- | A new cursor position.
--
-- See 'layoutMoveCursorVisually'.
--
data CursorPos
  = CursorPosPrevPara -- ^ The cursor should move to the previous paragraph.
  | CursorPos Int Int -- ^ The sum of the indices is the new cursor position.
  | CursorPosNextPara -- ^ The cursor should advance to the next paragraph.

-- | Move a cursor visually.
--
-- * Compute a new cursor position from a previous cursor position. A value
--   of @True@ for the direction will move it to the right, independant of
--   the underlying direction. Hence the cursor position might jump if
--   left-to-right text is mixed with right-to-left text.
--
-- * The first flag should be @True@ if this cursor is the strong cursor.
--   The strong cursor is the cursor of the base direction of the current
--   layout (see 'layoutSetAutoDir'). The weak cursor is that of the
--   opposite direction.
--
-- * The previous cursor position is given by @idx@. If this text at this
--   position is a cluster, the cursor will only move to the end or
--   beginning of the cluster as opposed to past the next character.
--   The return value is either 'CursorPosNextPara' if the cursor moved
--   beyond this paragraph, it is 'CursorPosPrevPara' if the cursor moved
--   in front of this paragraph and it is 'CursorPos' @idx@ @trail@ to denote
--   the new cursor position @idx@. Note that @idx@ will always denote an
--   insertion point, that is, @idx@ will never point into the middle of
--   a cluster. The @trail@ value can contain a positive
--   value if the current cursor position is at the end of the current line.
--   In this case, @idx@ points past the last character of this line while
--   @trail@ contains the number of characters that are reponsible for the
--   line break such as newlines. The actual cursor position is always
--   @idx+trail@ where the visual cursor should be shown.
--
layoutMoveCursorVisually :: PangoLayout
			 -> Bool -- ^ @True@ to create a strong cursor.
			 -> Int -- ^ The previous position.
			 -> Bool -- ^ @True@ if the cursor should move right.
			 -> IO CursorPos
layoutMoveCursorVisually (PangoLayout psRef plr) strong index dir = do
  (PangoString uc _ _) <- readIORef psRef
  alloca $ \idxPtr -> alloca $ \trailPtr -> do
    {#call unsafe layout_move_cursor_visually#} plr (fromBool strong)
      (fromIntegral (ofsToUTF index uc)) 0
      (if dir then 1 else (-1)) idxPtr trailPtr
    idx <- peek idxPtr
    trail <- peek trailPtr
    return (if idx==(-1) then CursorPosPrevPara else
	    if idx==maxBound then CursorPosNextPara else
	    CursorPos (ofsFromUTF (fromIntegral idx) uc) (fromIntegral trail))

-- | Compute the physical size of the layout.
--
-- * Computes the logical and the ink size of the 'Layout'. The
--   logical extend is used for positioning, the ink size is the smallest
--   bounding box that includes all character pixels. The ink size can be
--   smaller or larger that the logical layout.
--
layoutGetExtents :: PangoLayout -> IO (PangoRectangle, PangoRectangle)
layoutGetExtents (PangoLayout _ pl) =
  alloca $ \logPtr -> alloca $ \inkPtr -> do
  {#call unsafe layout_get_extents#} pl (castPtr logPtr) (castPtr inkPtr)
  log <- peek logPtr
  ink <- peek inkPtr
  return (fromRect log, fromRect ink)


-- | Compute the physical size of the layout.
--
-- * Computes the logical and the ink size of the 'Layout' in device units,
--   that is, pixels for a screen. Identical to 'layoutGetExtents' and
--   converting the 'PangoUnit's in the 'PangoRectangle' to integers.
--
layoutGetPixelExtents :: PangoLayout -> IO (Rectangle, Rectangle)
layoutGetPixelExtents (PangoLayout _ pl) =
  alloca $ \logPtr -> alloca $ \inkPtr -> do
  {#call unsafe layout_get_pixel_extents#} pl (castPtr logPtr) (castPtr inkPtr)
  log <- peek logPtr
  ink <- peek inkPtr
  return (log,ink)

-- | Ask for the number of lines in this layout.
--
layoutGetLineCount :: PangoLayout -> IO Int
layoutGetLineCount (PangoLayout _ pl) = liftM fromIntegral $
  {#call unsafe layout_get_line_count#} pl

-- | Extract a single lines of the layout.
--
-- * The given index starts from 0. The function throws an
--   'ArrayException' if the index is out of bounds.
--
-- * The lines of each layout are regenerated if any attribute changes.
--   Thus the returned list does not reflect the current state of lines
--   after a change has been made.
--
layoutGetLine :: PangoLayout -> Int -> IO LayoutLine
layoutGetLine (PangoLayout psRef pl) idx = do
  llPtr <- {#call unsafe layout_get_line#} pl (fromIntegral idx)
  if llPtr==nullPtr then 
     throwIO (ArrayException (IndexOutOfBounds
      ("Graphics.UI.Gtk.Pango.Layout.layoutGetLine: "++
       "no line at index "++show idx))) else do
  ll <- makeNewLayoutLineRaw llPtr
  {#call unsafe layout_line_ref#} ll
  return (LayoutLine psRef ll)

-- | Extract the lines of the layout.
--
-- * The lines of each layout are regenerated if any attribute changes.
--   Thus the returned list does not reflect the current state of lines
--   after a change has been made.
--
layoutGetLines :: PangoLayout -> IO [LayoutLine]
layoutGetLines (PangoLayout psRef pl) = do
  listPtr <- {#call unsafe layout_get_lines#} pl
  list <- readGSList listPtr
  pls <- mapM makeNewLayoutLineRaw list
  mapM_ {#call unsafe layout_line_ref#} pls
  return (map (LayoutLine psRef) pls)

-- | Create an iterator to examine a layout.
--
layoutGetIter :: PangoLayout -> IO LayoutIter
layoutGetIter (PangoLayout psRef pl) = do
  iterPtr <- {#call unsafe layout_get_iter#} pl
  liftM (LayoutIter psRef) $ makeNewLayoutIterRaw iterPtr

-- | Move to the next 'GlyphItem'.
--
-- * Returns @False@ if this was the last item in the layout.
--
layoutIterNextItem :: LayoutIter -> IO Bool
layoutIterNextItem (LayoutIter _ li) =
  liftM toBool $ {#call unsafe layout_iter_next_run#} li

-- | Move to the next char.
--
-- * Returns @False@ if this was the last char in the layout.
--
layoutIterNextChar :: LayoutIter -> IO Bool
layoutIterNextChar (LayoutIter _ li) =
  liftM toBool $ {#call unsafe layout_iter_next_char#} li

-- | Move to the next cluster.
--
-- * Returns @False@ if this was the last cluster in the layout.
--
layoutIterNextCluster :: LayoutIter -> IO Bool
layoutIterNextCluster (LayoutIter _ li) =
  liftM toBool $ {#call unsafe layout_iter_next_cluster#} li

-- | Move to the next line.
--
-- * Returns @False@ if this was the last line in the layout.
--
layoutIterNextLine :: LayoutIter -> IO Bool
layoutIterNextLine (LayoutIter _ li) =
  liftM toBool $ {#call unsafe layout_iter_next_line#} li

-- | Check if the iterator is on the last line.
--
-- * Returns @True@ if the iterator is on the last line of this
--   paragraph.
--
layoutIterAtLastLine :: LayoutIter -> IO Bool
layoutIterAtLastLine (LayoutIter _ li) =
  liftM toBool $ {#call unsafe layout_iter_at_last_line#} li

-- | Get the character index.
--
-- * Note that iterating forward by char moves in visual order, not
--   logical order, so indexes may not be sequential. Also, the index
--   may be equal to the length of the text in the layout.
--
layoutIterGetIndex :: LayoutIter -> IO Int
layoutIterGetIndex (LayoutIter psRef li) = do
  (PangoString uc _ _) <- readIORef psRef
  idx <- {#call unsafe layout_iter_get_index#} li
  return (ofsFromUTF (fromIntegral idx) uc)

-- | Query the vertical position within the layout.
--
-- * Gets the y position of the current line's baseline (origin at top
--   left of the entire layout).
--
layoutIterGetBaseline :: LayoutIter -> IO PangoUnit
layoutIterGetBaseline (LayoutIter _ li) = 
  liftM intToPu $ {#call unsafe pango_layout_iter_get_baseline#} li

-- | Retrieve the current 'GlyphItem' under the iterator.
--
-- * Each 'LayoutLine' contains a list of 'GlyphItem's. This function
--   returns the 'GlyphItem' under the current iterator. If the iterator
--   is positioned past the last charactor of the paragraph, the function
--   returns @Nothing@.
--
layoutIterGetItem :: LayoutIter -> IO (Maybe GlyphItem)
layoutIterGetItem (LayoutIter psRef li) = do
  giPtr <- {#call unsafe layout_iter_get_run#} li
  if giPtr==nullPtr then return Nothing else liftM Just $ do
    (PangoString uc _ _) <- readIORef psRef
    pirPtr <- {#get PangoGlyphItem.item#} giPtr
    gsrPtr <- {#get PangoGlyphItem.glyphs#} giPtr
    let dummy = {#call unsafe pango_item_copy#}
    let dummy = {#call unsafe pango_glyph_string_copy#}
    pirPtr' <- pango_item_copy pirPtr
    gsrPtr' <- pango_glyph_string_copy gsrPtr
    pir <- makeNewPangoItemRaw pirPtr'
    gsr <- makeNewGlyphStringRaw gsrPtr'
    ps <- readIORef psRef
    return (GlyphItem (PangoItem ps pir) gsr)

-- | Extract the line under the iterator.
--
layoutIterGetLine :: LayoutIter -> IO (Maybe LayoutLine)
layoutIterGetLine (LayoutIter psRef li) = do
  llPtr <- liftM castPtr $ {#call unsafe pango_layout_iter_get_line#} li
  if (llPtr==nullPtr) then return Nothing else do
    ll <- makeNewLayoutLineRaw llPtr
    {#call unsafe layout_line_ref#} ll
    return (Just (LayoutLine psRef ll))

-- | Retrieve a rectangle surrounding a character.
--
-- * Get the extents of the current character
--   (origin is the top left of the entire layout). Only logical extents
--   can sensibly be obtained for characters; ink extents make sense only
--   down to the level of clusters. 
--
layoutIterGetCharExtents :: LayoutIter -> IO PangoRectangle
layoutIterGetCharExtents (LayoutIter _ li) = alloca $ \logPtr -> 
  {#call unsafe layout_iter_get_char_extents#} li (castPtr logPtr) >>
  liftM fromRect (peek logPtr)

-- | Compute the physical size of the cluster.
--
-- * Computes the logical and the ink size of the cluster pointed to by
--   'LayoutIter'.
--
layoutIterGetClusterExtents :: LayoutIter -> IO (PangoRectangle,
						 PangoRectangle)
layoutIterGetClusterExtents (LayoutIter _ li) =
  alloca $ \logPtr -> alloca $ \inkPtr -> do
  {#call unsafe layout_iter_get_cluster_extents#} li (castPtr logPtr)
    (castPtr inkPtr)
  log <- peek logPtr
  ink <- peek inkPtr
  return (fromRect log, fromRect ink)

-- | Compute the physical size of the run.
--
-- * Computes the logical and the ink size of the run pointed to by
--   'LayoutIter'.
--
layoutIterGetRunExtents :: LayoutIter -> IO (PangoRectangle, PangoRectangle)
layoutIterGetRunExtents (LayoutIter _ li) =
  alloca $ \logPtr -> alloca $ \inkPtr -> do
  {#call unsafe layout_iter_get_run_extents#} li (castPtr logPtr)
    (castPtr inkPtr)
  log <- peek logPtr
  ink <- peek inkPtr
  return (fromRect log, fromRect ink)

-- | Retrieve vertical extent of this line.
--
-- * Divides the vertical space in the 'PangoLayout' being
--   iterated over between the lines in the layout, and returns the
--   space belonging to the current line. A line's range includes the
--   line's logical extents, plus half of the spacing above and below
--   the line, if 'pangoLayoutSetSpacing' has been called
--   to set layout spacing. The y positions are in layout coordinates
--   (origin at top left of the entire layout).
--
-- * The first element in the returned tuple is the start, the second is
--   the end of this line.
--
layoutIterGetLineYRange :: LayoutIter -> IO (PangoUnit, PangoUnit)
layoutIterGetLineYRange (LayoutIter _ li) =
  alloca $ \sPtr -> alloca $ \ePtr -> do
  {#call unsafe layout_iter_get_line_extents#} li (castPtr sPtr) (castPtr ePtr)
  start <- peek sPtr
  end <- peek ePtr
  return (intToPu start, intToPu end)

-- | Compute the physical size of the line.
--
-- * Computes the logical and the ink size of the line pointed to by
--   'LayoutIter'. See 'layoutGetExtents'.
--
-- * Extents are in layout coordinates (origin is the top-left corner
--   of the entire 'PangoLayout'). Thus the extents returned
--   by this function will be the same width\/height but not at the
--   same x\/y as the extents returned from
--   'pangoLayoutLineGetExtents'.
--
layoutIterGetLineExtents :: LayoutIter -> IO (PangoRectangle, PangoRectangle)
layoutIterGetLineExtents (LayoutIter _ li) =
  alloca $ \logPtr -> alloca $ \inkPtr -> do
  {#call unsafe layout_iter_get_line_extents#} li (castPtr logPtr)
    (castPtr inkPtr)
  log <- peek logPtr
  ink <- peek inkPtr
  return (fromRect log, fromRect ink)


-- | Compute the physical size of the line.
--
-- * Computes the logical and the ink size of the 'LayoutLine'. 
--   See 'layoutGetExtents'.
--
layoutLineGetExtents :: LayoutLine -> IO (PangoRectangle, PangoRectangle)
layoutLineGetExtents (LayoutLine _ ll) =
  alloca $ \logPtr -> alloca $ \inkPtr -> do
  {#call unsafe layout_line_get_extents#} ll (castPtr logPtr) (castPtr inkPtr)
  log <- peek logPtr
  ink <- peek inkPtr
  return (fromRect log, fromRect ink)

-- | Compute the physical size of the line.
--
-- * Computes the logical and the ink size of the 'LayoutLine'. 
--   See 'layoutGetExtents'. The returned values are in device units, that
--   is, pixels for the screen and points for printers.
--
layoutLineGetPixelExtents :: LayoutLine -> IO (Rectangle, Rectangle)
layoutLineGetPixelExtents (LayoutLine _ ll) =
  alloca $ \logPtr -> alloca $ \inkPtr -> do
  {#call unsafe layout_line_get_pixel_extents#} ll
    (castPtr logPtr) (castPtr inkPtr)
  log <- peek logPtr
  ink <- peek inkPtr
  return (log,ink)

-- | Request the horizontal position of a character.
--
layoutLineIndexToX :: LayoutLine
		   -> Int -- ^ the index into the string
		   -> Bool -- ^ return the beginning (@False@) or the end 
			    -- of the character
		   -> IO PangoUnit
layoutLineIndexToX (LayoutLine psRef ll) pos beg =
  alloca $ \intPtr -> do
    (PangoString uc _ _) <- readIORef psRef
    {#call unsafe layout_line_index_to_x#} ll (fromIntegral (ofsToUTF pos uc))
      (fromBool beg) intPtr
    liftM intToPu $ peek intPtr


-- | Request the character index of a given horizontal position.
--
-- * Converts from an x offset to the index of the corresponding
--   character within the text of the layout. If the @x@ parameter is
--   outside the line, a triple @(False, index, trailing)@ is returned
--   where @index@ and @trailing@ will point to the very
--   first or very last position in the line. This notion of first and last
--   position is based on the direction of the paragraph; for example,
--   if the direction is right-to-left, then an @x@ position to the
--   right of the line results in 0 being returned for @index@ and
--   @trailing@. An @x@ position to the left of the line results in
--   @index@ pointing to the (logical) last grapheme in the line and
--   trailing pointing to the number of characters in that grapheme.
--   The reverse is true for a left-to-right line. If the boolean flag in
--   the result is @True@ then @x@ was within the layout line and
--   @trailing@ indicates where in a cluster the @x@ position lay. It is
--   0 for the trailing edge of the cluster.
--
layoutLineXToIndex :: LayoutLine 
		   -> PangoUnit -- ^ The @x@ position.
		   -> IO (Bool, Int, Int)
layoutLineXToIndex (LayoutLine psRef ll) pos =
  alloca $ \idxPtr -> alloca $ \trailPtr -> do
    (PangoString uc _ _) <- readIORef psRef
    inside <- {#call unsafe layout_line_x_to_index#} ll
      (puToInt pos) idxPtr trailPtr
    idx <- peek idxPtr
    trail <- peek trailPtr
    return (toBool inside, ofsFromUTF (fromIntegral idx) uc,
	    fromIntegral trail)

-- FIXME: implement layout_line_get_x_ranges