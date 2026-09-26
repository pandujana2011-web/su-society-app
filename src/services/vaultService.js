import { supabase } from '../supabase';

export const vaultService = {
  /**
   * Initiate document upload
   */
  async initiateUpload({ propertyId, title, classification, fileName, fileSize, mimeType }) {
    const { data, error } = await supabase.rpc('fn_initiate_document_upload', {
      p_property_id: propertyId || null,
      p_title: title,
      p_classification: classification,
      p_file_name: fileName,
      p_file_size: fileSize,
      p_mime_type: mimeType
    });
    if (error) throw error;
    return data;
  },

  /**
   * Finalize document upload after Storage upload completes
   */
  async finalizeUpload(versionId, claimedSha256) {
    const { data, error } = await supabase.rpc('fn_finalize_document_upload', {
      p_version_id: versionId,
      p_claimed_sha256: claimedSha256
    });
    if (error) throw error;
    return data;
  },

  /**
   * Add a new version to an existing document
   */
  async addVersion({ documentId, fileName, fileSize, mimeType }) {
    const { data, error } = await supabase.rpc('fn_add_document_version', {
      p_document_id: documentId,
      p_file_name: fileName,
      p_file_size: fileSize,
      p_mime_type: mimeType
    });
    if (error) throw error;
    return data;
  },

  /**
   * Grant access to document
   */
  async grantAccess({ documentId, granteeType, granteeUserId, granteeRole, granteePropertyId, expiresAt }) {
    const { data, error } = await supabase.rpc('fn_grant_document_access', {
      p_document_id: documentId,
      p_grantee_type: granteeType,
      p_grantee_user_id: granteeUserId || null,
      p_grantee_role: granteeRole || null,
      p_grantee_property_id: granteePropertyId || null,
      p_expires_at: expiresAt || null
    });
    if (error) throw error;
    return data;
  },

  /**
   * Revoke access grant
   */
  async revokeAccess(grantId) {
    const { data, error } = await supabase.rpc('fn_revoke_document_access', {
      p_grant_id: grantId
    });
    if (error) throw error;
    return data;
  },

  /**
   * Request 15-minute Storage signed download URL
   */
  async generateDownloadUrl(documentId, versionId = null) {
    const { data, error } = await supabase.rpc('fn_generate_document_download_url', {
      p_document_id: documentId,
      p_version_id: versionId
    });
    if (error) throw error;
    return data;
  },

  /**
   * Archive document (Admin only)
   */
  async archiveDocument(documentId) {
    const { data, error } = await supabase.rpc('fn_archive_vault_document', {
      p_document_id: documentId
    });
    if (error) throw error;
    return data;
  },

  /**
   * Delete document (Admin only)
   */
  async deleteDocument(documentId) {
    const { data, error } = await supabase.rpc('fn_delete_vault_document', {
      p_document_id: documentId
    });
    if (error) throw error;
    return data;
  }
};
