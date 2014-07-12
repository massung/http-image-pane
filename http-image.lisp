;;;; HTTP Image Downloader for LispWorks
;;;;
;;;; Copyright (c) 2013 by Jeffrey Massung
;;;;
;;;; This file is provided to you under the Apache License,
;;;; Version 2.0 (the "License"); you may not use this file
;;;; except in compliance with the License.  You may obtain
;;;; a copy of the License at
;;;;
;;;;    http://www.apache.org/licenses/LICENSE-2.0
;;;;
;;;; Unless required by applicable law or agreed to in writing,
;;;; software distributed under the License is distributed on an
;;;; "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
;;;; KIND, either express or implied.  See the License for the
;;;; specific language governing permissions and limitations
;;;; under the License.
;;;;

(defpackage :http-image
  (:use :cl :lw :mp :http)
  (:export
   #:http-image-type
   #:http-image-download
   #:http-image-cache-clear

   ;; classes
   #:http-image-pane

   ;; pane methods
   #:http-image-pane-url
   #:http-image-pane-fit-pane
   #:http-image-pane-image
   #:http-image-pane-error
   #:http-image-pane-process
   #:http-image-pane-refresh
   #:http-image-pane-clear))

(in-package :http-image)

(defconstant +image-types+
  '(("x-icon" :ico)
    ("ico"    :ico)
    ("png"    :png)
    ("jpg"    :jpeg)
    ("jpe"    :jpeg)
    ("jpeg"   :jpeg)
    ("gif"    :gif)
    ("bmp"    :bmp))
  "Known extensions for images.")

(defvar *http-image-cache* (make-hash-table :test 'equal)
  "Successfully downloaded images are put here.")

(defun http-image-cache-clear ()
  "Wipe all external images from the image cache."
  (prog1
      nil
    (sys:atomic-exchange *http-image-cache* (make-hash-table :test 'equal))))

(defun http-image-type (resp)
  "Return the type for this image."
  (let ((type (let ((content-type (http-header resp "Content-Type")))
                (when (and content-type (eql (search "image/" content-type) 0))
                  (subseq content-type 6))))
        (ext (pathname-type (pathname (url-path (request-url (response-request resp)))))))
                     
    ;; use the Content-Type, if that fails, try the file extension
    (second (or (assoc type +image-types+ :test #'string-equal)
                (assoc ext +image-types+ :test #'string-equal)))))

(defun http-image-download (url callback &key reload (timeout 30))
  "Start a process to download the image into an external-image representation."
  (with-url (url url)
    (flet ((download ()
             (let ((cached-image (hcl:with-hash-table-locked *http-image-cache*
                                   (gethash (format-url url) *http-image-cache*))))

               ;; if the image hasn't already been cached, download it
               (unless cached-image
                 (handler-case
                     (with-response (resp (http-get url :redirect-limit 2) :timeout timeout :errorp t)
                       (if-let (type (http-image-type resp))
                           (let ((bytes (map '(vector (unsigned-byte 8)) #'char-code (response-body resp))))
                             (setf cached-image (make-instance 'gp:external-image :data bytes :type type))
                             
                             ;; write the external image to the cache
                             (hcl:with-hash-table-locked *http-image-cache*
                               (setf (gethash (format-url url) *http-image-cache*) cached-image)))
                         (error "Unknown image type.")))
                   (error (c)
                     (funcall callback nil c))))
               
               ;; successfully downloaded
               (funcall callback cached-image))))

      ;; clear the cache entry if reloading
      (when reload
        (hcl:with-hash-table-locked *http-image-cache*
          (remhash (format-url url) *http-image-cache*)))

      ;; start the download
      (process-run-function "Image download" '() #'download))))