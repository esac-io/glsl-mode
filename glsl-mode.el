;;; glsl-mode.el --- major mode for Open GLSL shader files
;;
;; Copyright (C) 1999, 2000, 2001 Free Software Foundation, Inc.
;; Copyright (C) 2011, 2014, 2019 Jim Hourihan
;; Copyright (C) 2020 esac
;;
;; Authors: Xavier.Decoret@imag.fr,
;;          Jim Hourihan <jimhourihan ~at~ gmail.com> (updated for 4.6, etc)
;;          esac
;;
;; Keywords: languages OpenGL GPU SPIR-V Vulkan
;; Version: 0.0.1 Alpha
;; URL: https://github.com/esac-io/glsl-mode
;; Reference: http://artis.inrialpes.fr/~Xavier.Decoret/resources/glsl-mode
;;
;; This file is NOT part of GNU Emacs.
;;
;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;; Major mode for editing OpenGLSL grammar files, usually files
;; ending with .vert, .frag, .glsl, .geom. Is is based on
;; c-mode plus some features and pre-specified fonts and
;; faces properties.
;;
;; Modifications from the 1.0 version of glsl-mode (jimhourihan):
;;  * Removed original optimized regexps for font-lock-keywords and
;;    replaced with keyword lists for easier maintenance
;;  * Added customization group and faces
;;  * Preprocessor faces
;;  * Updated to GLSL 4.6
;;  * Separate deprecated symbols
;;  * Made _ part of a word
;;  * man page lookup at opengl.org
;;
;; This package provides the following features:
;;  * Syntax coloring (via font-lock) for grammar symbols and
;;    builtin functions and variables for up to GLSL version 4.6
;;  * Indentation for the current line (TAB) and selected region (C-M-\).
;;  * Switching between file.vert and file.frag
;;    with S-lefttab (via ff-find-other-file)
;;
;;; Installation:
;;
;; This file requires Emacs-20.3 or higher and package cc-mode.
;;
;; If glsl-mode is not part of your distribution, put this file into your
;; load-path and the following into your Emacs initialization file
;; (usually init.el):
;;
;;   (autoload 'glsl-mode "glsl-mode" nil t)
;;
;;   (add-to-list 'auto-mode-alist '("\\.glsl\\'" . glsl-mode))
;;   (add-to-list 'auto-mode-alist '("\\.vert\\'" . glsl-mode))
;;   (add-to-list 'auto-mode-alist '("\\.frag\\'" . glsl-mode))
;;   (add-to-list 'auto-mode-alist '("\\.geom\\'" . glsl-mode))
;;
;; Reference:
;;
;; https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.pdf
;;
;;; Code:

(require 'align)
(require 'cc-mode)

;; required and optional libraries
(eval-when-compile
  (require 'find-file)
  (require 'easymenu))

(defgroup glsl nil
  "OpenGL Shading Language Major Mode."
  :group 'languages)

(defgroup glsl-faces nil
  "Faces used by `glsl-mode'."
  :group 'glsl
  :group 'faces)

(defconst glsl-language-version "4.6"
  "GLSL language version number.")

(defconst gl-version "4.6"
  "OpenGL major mode version number.")

(defcustom glsl-additional-types nil
  "List of additional keywords to be considered types.

These are added to the `glsl-type-list' and are fontified using the
`glsl-type-face'.

Examples of existing types include \"float\", \"vec4\", and \"int\"."

  :type '(repeat (string :tag "Type Name"))
  :group 'glsl)

(defcustom glsl-additional-qualifiers nil
  "List of additional keywords to be considered qualifiers.

These are added to the `glsl-qualifier-list' and are
fontified using the `glsl-qualifier-face'.

Examples of existing qualifiers include \"const\", \"in\", and \"out\"."

  :type '(repeat (string :tag "Qualifier Name"))
  :group 'glsl)

(defcustom glsl-additional-keywords nil
  "List of additional GLSL keywords.

These are added to the `glsl-keyword-list' and are fontified
using the `glsl-keyword-face'.

Example existing keywords include \"while\", \"if\", and \"return\"."

  :type '(repeat (string :tag "Keyword"))
  :group 'glsl)

(defcustom glsl-additional-built-ins nil
  "List of additional functions to be considered built-in. These
are added to the `glsl-builtin-list' and are fontified using the
`glsl-builtin-face'."
  :type '(repeat (string :tag "Keyword"))
  :group 'glsl)

(defvar glsl-mode-menu nil
  "Menu for GLSL mode.")

(defvar glsl-mode-hook nil
  "Hook run after entering `glsl-mode'.")

(defvar glsl-mode-map
  (let ((glsl-mode-map (make-sparse-keymap)))
    (define-key glsl-mode-map [S-iso-lefttab] 'ff-find-other-file)
    glsl-mode-map)
  "The `glsl-mode' standard keymap.")

(defvar glsl-mode-syntax-table
  (let ((glsl-mode-syntax-table (make-syntax-table)))
    (modify-syntax-entry ?/ ". 124b" glsl-mode-syntax-table)
    (modify-syntax-entry ?* ". 23" glsl-mode-syntax-table)
    (modify-syntax-entry ?\n "> b" glsl-mode-syntax-table)
    (modify-syntax-entry ?_ "w" glsl-mode-syntax-table)
    glsl-mode-syntax-table)
  "Syntax table for glsl-mode.")

(defvar glsl-other-file-alist
  '(("\\.frag$" (".vert"))
    ("\\.vert$" (".frag")))
  "Extensions to find given the current file's extension.")

(defface glsl-type-face
  '((t (:inherit font-lock-type-face)))
  "Type face.")

(defface glsl-builtin-face
  '((t (:inherit font-lock-builtin-face)))
  "Builtin face.")

(defface glsl-deprecated-builtin-face
  '((t (:inherit font-lock-warning-face)))
  "Deprecated builtin face.")

(defface glsl-qualifier-face
  '((t (:inherit font-lock-keyword-face)))
  "Qualifier face.")

(defface glsl-keyword-face
  '((t (:inherit font-lock-keyword-face)))
  "Keyword face.")

(defface glsl-deprecated-keyword-face
  '((t (:inherit font-lock-warning-face)))
  "Deprecated keyword face.")

(defface glsl-variable-name-face
  '((t (:inherit font-lock-variable-name-face)))
  "Variable face.")

(defface glsl-deprecated-variable-name-face
  '((t (:inherit font-lock-warning-face)))
  "Deprecated variable face.")

(defface glsl-reserved-keyword-face
  '((t (:inherit glsl-keyword-face)))
  "Reserved keyword face.")

(defface glsl-preprocessor-face
  '((t (:inherit font-lock-preprocessor-face)))
  "Preprocessor face.")

(defun glsl-ppre (strings)
  "Return a regexp to match a string in the list STRINGS."
  (format "\\<\\(%s\\)\\>" (regexp-opt strings)))

(defvar glsl-type-list
  '("float" "double" "int" "void" "bool" "true" "false" "mat2" "mat3"
    "mat4" "dmat2" "dmat3" "dmat4" "mat2x2" "mat2x3" "mat2x4" "dmat2x2"
    "dmat2x3" "dmat2x4" "mat3x2" "mat3x3" "mat3x4" "dmat3x2" "dmat3x3"
    "dmat3x4" "mat4x2" "mat4x3" "mat4x4" "dmat4x2" "dmat4x3" "dmat4x4" "vec2"
    "vec3" "vec4" "ivec2" "ivec3" "ivec4" "bvec2" "bvec3" "bvec4" "dvec2"
    "dvec3" "dvec4" "uint" "uvec2" "uvec3" "uvec4" "atomic_uint"
    "sampler1D" "sampler2D" "sampler3D" "samplerCube" "sampler1DShadow"
    "sampler2DShadow" "samplerCubeShadow" "sampler1DArray" "sampler2DArray"
    "sampler1DArrayShadow" "sampler2DArrayShadow" "isampler1D" "isampler2D"
    "isampler3D" "isamplerCube" "isampler1DArray" "isampler2DArray"
    "usampler1D" "usampler2D" "usampler3D" "usamplerCube" "usampler1DArray"
    "usampler2DArray" "sampler2DRect" "sampler2DRectShadow" "isampler2DRect"
    "usampler2DRect" "samplerBuffer" "isamplerBuffer" "usamplerBuffer"
    "sampler2DMS" "isampler2DMS" "usampler2DMS" "sampler2DMSArray"
    "isampler2DMSArray" "usampler2DMSArray" "samplerCubeArray"
    "samplerCubeArrayShadow" "isamplerCubeArray" "usamplerCubeArray"
    "image1D" "iimage1D" "uimage1D" "image2D" "iimage2D" "uimage2D" "image3D"
    "iimage3D" "uimage3D" "image2DRect" "iimage2DRect" "uimage2DRect"
    "imageCube" "iimageCube" "uimageCube" "imageBuffer" "iimageBuffer"
    "uimageBuffer" "image1DArray" "iimage1DArray" "uimage1DArray"
    "image2DArray" "iimage2DArray" "uimage2DArray" "imageCubeArray"
    "iimageCubeArray" "uimageCubeArray" "image2DMS" "iimage2DMS" "uimage2DMS"
    "image2DMSArray" "iimage2DMSArray" "uimage2DMSArray")
  "Glsl type table/list.")

(defvar glsl-qualifier-list
  '("in" "out" "flat" "lowp"
    "highp" "const" "patch" "inout"
    "smooth" "sample" "uniform" "varying"
    "buffer" "shared" "layout" "mediump"
    "centroid" "coherent" "volatile" "restrict"
    "readonly" "writeonly" "attribute" "invariant"
    "noperspective")
  "Glsl qualifier table/list.")

(defvar glsl-keyword-list
  '("break" "continue" "do" "for"
    "while" "if" "else" "subroutine"
    "discard" "return" "precision"
    "struct" "switch" "default" "case")
  "Glsl keyword table/list.")

(defvar glsl-reserved-list
  '("input" "output" "asm" "class" "union"
    "enum" "typedef" "template" "this"
    "packed" "resource" "goto" "inline" "noinline"
    "common" "partition" "active" "long" "short"
    "half" "fixed" "unsigned" "superp"
    "public" "static" "extern" "external" "interface"
    "hvec2" "hvec3" "hvec4" "fvec2" "fvec3" "fvec4"
    "filter" "sizeof" "cast" "namespace" "using"
    "sampler3DRect")
  "Glsl reserved table/list.")

;; centroid is deprecated when used with varying
(defvar glsl-deprecated-qualifier-list
  '("varying" "attribute")
  "Glsl deprecated qualifier table/list.")

(defvar glsl-builtin-list
  '("abs" "acos" "acosh" "all" "any" "anyInvocation" "allInvocations"
    "allInvocationsEqual" "asin" "asinh" "atan" "atanh"
    "atomicAdd" "atomicMin" "atomicMax" "atomicAnd" "atomicOr"
    "atomicXor" "atomicExchange" "atomicCompSwap"
    "atomicCounter" "atomicCounterDecrement" "atomicCounterIncrement"
    "atomicCounterAdd" "atomicCounterSubtract" "atomicCounterMin"
    "atomicCounterMax" "atomicCounterAnd" "atomicCounterOr"
    "atomicCounterXor" "atomicCounterExchange" "atomicCounterCompSwap"
    "barrier" "bitCount" "bitfieldExtract" "bitfieldInsert" "bitfieldReverse"
    "ceil" "clamp" "cos" "cosh" "cross" "degrees" "determinant" "dFdx" "dFdy"
    "dFdyFine" "dFdxFine" "dFdyCoarse" "dFdxCoarse" "distance" "dot"
    "fwidthFine" "fwidthCoarse" "EmitStreamVertex" "EmitStreamPrimitive"
    "EmitVertex" "EndPrimitive" "EndStreamPrimitive" "equal" "exp" "exp2"
    "faceforward" "findLSB" "findMSB" "floatBitsToInt" "floatBitsToUint"
    "floor" "fma" "fract" "frexp" "fwidth" "greaterThan" "greaterThanEqual"
    "groupMemoryBarrier" "imageAtomicAdd" "imageAtomicAnd"
    "imageAtomicCompSwap" "imageAtomicExchange" "imageAtomicMax"
    "imageAtomicMin" "imageAtomicOr" "imageAtomicXor"
    "imageLoad" "imageSize" "imageStore" "imulExtended" "intBitsToFloat"
    "imageSamples" "interpolateAtCentroid" "interpolateAtOffset"
    "interpolateAtSample" "inverse" "inversesqrt" "isinf" "isnan"
    "ldexp" "length" "lessThan" "lessThanEqual" "log" "log2"
    "matrixCompMult" "max" "memoryBarrier" "memoryBarrierAtomicCounter"
    "memoryBarrierBuffer" "memoryBarrierShared" "memoryBarrierImage"
    "memoryBarrier" "min" "mix" "mod" "modf"
    "normalize" "not" "notEqual" "outerProduct"
    "packDouble2x32" "packHalf2x16" "packSnorm2x16" "packSnorm4x8"
    "packUnorm2x16" "packUnorm4x8" "pow" "radians" "reflect" "refract"
    "round" "roundEven" "sign" "sin" "sinh" "smoothstep" "sqrt" "step" "tan"
    "tanh" "texelFetch" "texelFetchOffset" "texture" "textureGather"
    "textureGatherOffset" "textureGatherOffsets" "textureGrad" "textureSamples"
    "textureGradOffset" "textureLod" "textureLodOffset" "textureOffset"
    "textureProj" "textureProjGrad" "textureProjGradOffset" "textureProjLod"
    "textureProjLodOffset" "textureProjOffset"
    "textureQueryLevels" "textureQueryLod"
    "textureSize" "transpose" "trunc" "uaddCarry" "uintBitsToFloat"
    "umulExtended" "unpackDouble2x32" "unpackHalf2x16" "unpackSnorm2x16"
    "unpackSnorm4x8" "unpackUnorm2x16" "unpackUnorm4x8" "usubBorrow")
  "Glsl builtin table/list.")

(defvar glsl-deprecated-builtin-list
  '("noise1" "noise2" "noise3" "noise4"
    "texture1D" "texture1DProj" "texture1DLod" "texture1DProjLod"
    "texture2D" "texture2DProj" "texture2DLod" "texture2DProjLod"
    "texture2DRect" "texture2DRectProj"
    "texture3D" "texture3DProj" "texture3DLod" "texture3DProjLod"
    "shadow1D" "shadow1DProj" "shadow1DLod" "shadow1DProjLod"
    "shadow2D" "shadow2DProj" "shadow2DLod" "shadow2DProjLod"
    "textureCube" "textureCubeLod")
  "Glsl deprecated builtin table/list.")

(defvar glsl-deprecated-variables-list
  '("gl_FragColor" "gl_FragData"
    "gl_MaxVarying" "gl_MaxVaryingFloats"
    "gl_MaxVaryingComponents")
  "Glsl deprecated variables table/list.")

(defvar glsl-preprocessor-directive-list
  '("define" "undef" "if" "ifdef"
    "ifndef" "else" "elif" "endif"
    "error" "pragma" "extension"
    "version" "line")
  "Glsl pre-processor directive table/list.")

(defvar glsl-preprocessor-expr-list
  '("defined" "##")
  "Glsl pre-processor expression table/list.")

(defvar glsl-preprocessor-builtin-list
  '("__LINE__" "__FILE__" "__VERSION__")
  "Glsl pre-processor builtin table/list.")

(defvar glsl-font-lock-keywords-1 nil
  "Highlighting expressions for GLSL mode.")

(defvar glsl-font-lock-keywords glsl-font-lock-keywords-1
  "Default highlighting expressions for GLSL mode.")

(easy-menu-define glsl-menu glsl-mode-map
  "GLSL Menu"
  `("GLSL"
    ["Comment Out Region" comment-region
     (c-fn-region-is-active-p)]
    ["Uncomment Region"
     (comment-region (region-beginning)
                     (region-end) '(4))
     (c-fn-region-is-active-p)]
    ["Indent Expression" c-indent-exp
     (memq (char-after) '(?\( ?\[ ?\{))]
    ["Indent Line or Region"  c-indent-line-or-region t]
    ["Fill Comment Paragraph" c-fill-paragraph t]
    "----"
    ["Backward Statement" c-beginning-of-statement t]
    ["Forward Statement" c-end-of-statement t]
    "----"
    ["Up Conditional" c-up-conditional t]
    ["Backward Conditional" c-backward-conditional t]
    ["Forward Conditional" c-forward-conditional t]
    "----"
    ["Backslashify" c-backslash-region (c-fn-region-is-active-p)]))

(defun glsl--initialize-cc-resources ()
  "Initialize `cc-mode' resources."
  (c-initialize-cc-mode t)
  (c-init-language-vars-for 'c-mode)
  (c-common-init 'c-mode)
  (cc-imenu-init cc-imenu-c++-generic-expression))

(defun glsl--set-font-lock ()
  "Set default font locks."
  (set (make-local-variable 'font-lock-defaults)
       glsl-font-lock-keywords))

(defun glsl--set-find-other-file ()
  "Set `ff-other-file-alist'.
Alist of extensions to find given the current
file’s extension."
  (set (make-local-variable 'ff-other-file-alist)
       'glsl-other-file-alist))

(defun glsl--setup-comment-strings ()
  "Setup new comment related strings."
  (set (make-local-variable 'comment-start) "// ")
  (set (make-local-variable 'comment-end) "")
  (set (make-local-variable 'comment-padding) ""))

;;;###autoload
(define-derived-mode glsl-mode prog-mode "GLSL"
  "Major mode for editing GLSL shader files."
  ;; toggle Abbrev mode in the current buffer
  (setq abbrev-mode t)
  ;; initialize cc resources
  (glsl--initialize-cc-resources)
  ;; set default font lock
  ;; (glsl--set-font-lock)
  ;; set local find other file associative list
  (glsl--set-find-other-file)
  ;; setup comment GLSL comment strings
  (glsl--setup-comment-strings)
  ;; add the menu entries to the menu bar
  (easy-menu-add glsl-menu)
  ;; add hooks
  (add-to-list 'align-c++-modes 'glsl-mode)
  ;; run cc-mode hooks
  (c-run-mode-hooks 'c-mode-common-hook)
  ;; run glsl mode hooks
  (run-mode-hooks 'glsl-mode-hook)
  ;; run after hook
  :after-hook
  (progn (c-make-noise-macro-regexps)
         (c-make-macro-with-semi-re)
         (c-update-modeline)))

(provide 'glsl-mode)

;;; glsl-mode.el ends here
