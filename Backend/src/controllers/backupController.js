const model = require('../models/backupModel');
const path = require('path');
const fs = require('fs');
const { success, error } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const rows = await model.listBackups();
    return success(res, rows, 'Backups list');
  } catch (err) { return error(res, err.message, 500); }
};

exports.create = async (req, res, next) => {
  try {
    const result = await model.backup();
    res.locals.auditDetails = { fileName: result.fileName, size: result.size };
    return success(res, result, 'Backup created', null, 201);
  } catch (err) {
    return error(res, 'Backup failed: ' + err.message, 500, 'BACKUP_FAILED');
  }
};

exports.download = async (req, res, next) => {
  try {
    const fileName = req.params.fileName;
    const backupsDir = path.join(__dirname, '..', '..', 'uploads', 'backups');
    const fullPath = path.join(backupsDir, fileName);
    if (!fs.existsSync(fullPath)) return error(res, 'File not found', 404, 'NOT_FOUND');
    return res.download(fullPath, fileName);
  } catch (err) { return error(res, err.message, 500); }
};

exports.restore = async (req, res, next) => {
  try {
    const { fileName } = req.body;
    if (!fileName) return error(res, 'fileName required', 400, 'BAD_REQUEST');
    const result = await model.restore(fileName);
    res.locals.auditDetails = { fileName };
    return success(res, result, 'Database restored');
  } catch (err) {
    return error(res, 'Restore failed: ' + err.message, err.status || 500, 'RESTORE_FAILED');
  }
};

exports.remove = async (req, res, next) => {
  try {
    await model.deleteBackup(req.params.fileName);
    return success(res, null, 'Backup deleted');
  } catch (err) { return error(res, err.message, err.status || 500); }
};
