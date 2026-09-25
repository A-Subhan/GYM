const sharp = require('sharp');

const service = require('../services/memberService');
const {
  success,
  error,
  paginate
} = require('../utils/response');

function canSelectBranch(req) {
  return (
    req.user?.isSuperAdmin === true ||
    req.user?.isOwner === true ||
    req.user?.isAdmin === true
  );
}

function getUserBranchId(req) {
  return req.user?.branchId
    ? parseInt(req.user.branchId, 10)
    : null;
}

async function compressPhoto(file) {
  if (!file) {
    return null;
  }

  return sharp(file.buffer)
    .rotate()
    .resize({
      width: 800,
      height: 800,
      fit: 'inside',
      withoutEnlargement: true
    })
    .jpeg({
      quality: 80,
      mozjpeg: true
    })
    .toBuffer();
}

exports.list = async (req, res) => {
  try {
    const {
      page,
      pageSize,
      search,
      Status,
      TrainerID,
      BranchID
    } = req.query;

    const branchSelectionAllowed =
      canSelectBranch(req);

    const branchId = branchSelectionAllowed
      ? BranchID
        ? parseInt(BranchID, 10)
        : null
      : getUserBranchId(req);

    const result = await service.list({
      page: parseInt(page, 10) || 1,
      pageSize:
        parseInt(pageSize, 10) || 20,
      search: search || null,
      branchId,
      status: Status || null,
      trainerId: TrainerID
        ? parseInt(TrainerID, 10)
        : null
    });

    return paginate(
      res,
      result.rows,
      result.total,
      parseInt(page, 10) || 1,
      parseInt(pageSize, 10) || 20,
      'Members list'
    );
  } catch (err) {
    console.error(
      '[members] list error:',
      err
    );

    return error(
      res,
      err.message,
      500
    );
  }
};

exports.get = async (req, res) => {
  try {
    const memberId = parseInt(
      req.params.id,
      10
    );

    if (!Number.isInteger(memberId)) {
      return error(
        res,
        'Invalid member ID',
        400,
        'BAD_REQUEST'
      );
    }

    const member =
      await service.get(memberId);

    if (!member) {
      return error(
        res,
        'Member not found',
        404,
        'NOT_FOUND'
      );
    }

    if (
      !canSelectBranch(req) &&
      Number(member.BranchID) !==
        getUserBranchId(req)
    ) {
      return error(
        res,
        'You cannot access this member',
        403,
        'BRANCH_ACCESS_DENIED'
      );
    }

    return success(
      res,
      member,
      'Member details'
    );
  } catch (err) {
    console.error(
      '[members] get error:',
      err
    );

    return error(
      res,
      err.message,
      500
    );
  }
};

exports.photo = async (req, res) => {
  try {
    const memberId = parseInt(
      req.params.id,
      10
    );

    if (!Number.isInteger(memberId)) {
      return error(
        res,
        'Invalid member ID',
        400,
        'BAD_REQUEST'
      );
    }

    const member =
      await service.get(memberId);

    if (!member) {
      return error(
        res,
        'Member not found',
        404,
        'NOT_FOUND'
      );
    }

    if (
      !canSelectBranch(req) &&
      Number(member.BranchID) !==
        getUserBranchId(req)
    ) {
      return error(
        res,
        'You cannot access this member',
        403,
        'BRANCH_ACCESS_DENIED'
      );
    }

    const photo =
      await service.getPhoto(memberId);

    if (!photo) {
      return error(
        res,
        'Member photo not found',
        404,
        'PHOTO_NOT_FOUND'
      );
    }

    res.setHeader(
      'Content-Type',
      'image/jpeg'
    );

    res.setHeader(
      'Cache-Control',
      'private, max-age=300'
    );

    return res.send(photo);
  } catch (err) {
    console.error(
      '[members] photo error:',
      err
    );

    return error(
      res,
      err.message,
      500
    );
  }
};

exports.getProfile = async (
  req,
  res
) => {
  try {
    const memberId = parseInt(
      req.params.id,
      10
    );

    if (!Number.isInteger(memberId)) {
      return error(
        res,
        'Invalid member ID',
        400,
        'BAD_REQUEST'
      );
    }

    const member =
      await service.get(memberId);

    if (!member) {
      return error(
        res,
        'Member not found',
        404,
        'NOT_FOUND'
      );
    }

    if (
      !canSelectBranch(req) &&
      Number(member.BranchID) !==
        getUserBranchId(req)
    ) {
      return error(
        res,
        'You cannot access this member',
        403,
        'BRANCH_ACCESS_DENIED'
      );
    }

    const [
      payments,
      attendance,
      memberships,
      progress
    ] = await Promise.all([
      service.getPayments(memberId),
      service.getAttendance(
        memberId,
        null,
        null
      ),
      service.getMemberships(
        memberId
      ),
      service.getProgress(memberId)
    ]);

    return success(
      res,
      {
        member,
        payments,
        attendance,
        memberships,
        progress
      },
      'Member full profile'
    );
  } catch (err) {
    console.error(
      '[members] profile error:',
      err
    );

    return error(
      res,
      err.message,
      500
    );
  }
};

exports.create = async (
  req,
  res
) => {
  try {
    const data = {
      ...req.body
    };

    if (canSelectBranch(req)) {
      if (!data.BranchID) {
        return error(
          res,
          'BranchID is required',
          400,
          'BAD_REQUEST'
        );
      }

      data.BranchID = parseInt(
        data.BranchID,
        10
      );
    } else {
      const userBranchId =
        getUserBranchId(req);

      if (!userBranchId) {
        return error(
          res,
          'Your account is not assigned to a branch',
          403,
          'BRANCH_REQUIRED'
        );
      }

      data.BranchID =
        userBranchId;
    }

    if (req.file) {
      data.Photo =
        await compressPhoto(
          req.file
        );
    }

    const result =
      await service.create(
        data,
        req.user.userId
      );

    res.locals.entityId =
      result.MemberID;

    /* Optional membership assignment at creation time
       (the old Active Memberships page was removed) */
    let membership = null;

    if (data.MembershipPlanID) {
      try {
        membership =
          await service.assignMembership(
            {
              MemberID: result.MemberID,
              PlanID: data.MembershipPlanID,
              StartDate: data.JoiningDate
            },
            req.user.userId
          );
      } catch (mErr) {
        console.error(
          '[members] membership assignment error:',
          mErr
        );
      }
    }

    return success(
      res,
      { ...result, membership },
      'Member created',
      null,
      201
    );
  } catch (err) {
    console.error(
      '[members] create error:',
      err
    );

    if (
      /CNIC already exists/i.test(
        err.message
      )
    ) {
      return error(
        res,
        'CNIC already exists',
        409,
        'DUPLICATE_CNIC'
      );
    }

    if (
      /duplicate|unique/i.test(
        err.message
      )
    ) {
      return error(
        res,
        'Member code already exists',
        409,
        'DUPLICATE_CODE'
      );
    }

    if (
      /branch/i.test(
        err.message
      )
    ) {
      return error(
        res,
        err.message,
        400,
        'INVALID_BRANCH'
      );
    }

    return error(
      res,
      err.message,
      500
    );
  }
};

exports.update = async (
  req,
  res
) => {
  try {
    const memberId = parseInt(
      req.params.id,
      10
    );

    if (!Number.isInteger(memberId)) {
      return error(
        res,
        'Invalid member ID',
        400,
        'BAD_REQUEST'
      );
    }

    const member =
      await service.get(memberId);

    if (!member) {
      return error(
        res,
        'Member not found',
        404,
        'NOT_FOUND'
      );
    }

    if (
      !canSelectBranch(req) &&
      Number(member.BranchID) !==
        getUserBranchId(req)
    ) {
      return error(
        res,
        'You cannot edit a member from another branch',
        403,
        'BRANCH_ACCESS_DENIED'
      );
    }

    const data = {
      BranchID:
        canSelectBranch(req) &&
        req.body.BranchID
          ? parseInt(
              req.body.BranchID,
              10
            )
          : member.BranchID,

      FullName:
        req.body.FullName ??
        member.FullName,

      FatherName:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'FatherName'
        )
          ? req.body.FatherName || null
          : member.FatherName,

      Gender:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'Gender'
        )
          ? req.body.Gender || null
          : member.Gender,

      DOB:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'DOB'
        )
          ? req.body.DOB || null
          : member.DOB,

      CNIC:
        req.body.CNIC ??
        member.CNIC,

      Mobile:
        req.body.Mobile ??
        member.Mobile,

      WhatsApp:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'WhatsApp'
        )
          ? req.body.WhatsApp || null
          : member.WhatsApp,

      Email:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'Email'
        )
          ? req.body.Email || null
          : member.Email,

      Address:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'Address'
        )
          ? req.body.Address || null
          : member.Address,

      EmergencyContact:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'EmergencyContact'
        )
          ? req.body.EmergencyContact ||
            null
          : member.EmergencyContact,

      JoiningDate:
        req.body.JoiningDate ??
        member.JoiningDate,

      TrainerID:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'TrainerID'
        )
          ? req.body.TrainerID || null
          : member.TrainerID,

      HeightFeet:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'HeightFeet'
        )
          ? req.body.HeightFeet || null
          : member.HeightFeet,

      HeightInches:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'HeightInches'
        )
          ? req.body.HeightInches || null
          : member.HeightInches,

      Weight:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'Weight'
        )
          ? req.body.Weight || null
          : member.Weight,

      MedicalNotes:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'MedicalNotes'
        )
          ? req.body.MedicalNotes || null
          : member.MedicalNotes,

      Status:
        Object.prototype.hasOwnProperty.call(
          req.body,
          'Status'
        )
          ? req.body.Status || null
          : member.Status,

      Photo: null
    };

    if (req.file) {
      data.Photo =
        await compressPhoto(
          req.file
        );
    }

    await service.update(
      memberId,
      data,
      req.user.userId
    );

    return success(
      res,
      null,
      'Member updated'
    );
  } catch (err) {
    console.error(
      '[members] update error:',
      err
    );

    if (
      /CNIC already exists/i.test(
        err.message
      )
    ) {
      return error(
        res,
        'CNIC already exists',
        409,
        'DUPLICATE_CNIC'
      );
    }

    if (
      /Member not found/i.test(
        err.message
      )
    ) {
      return error(
        res,
        'Member not found',
        404,
        'NOT_FOUND'
      );
    }

    return error(
      res,
      err.message,
      500
    );
  }
};

exports.remove = async (
  req,
  res
) => {
  try {
    const memberId = parseInt(
      req.params.id,
      10
    );

    if (!Number.isInteger(memberId)) {
      return error(
        res,
        'Invalid member ID',
        400,
        'BAD_REQUEST'
      );
    }

    const member =
      await service.get(memberId);

    if (!member) {
      return error(
        res,
        'Member not found',
        404,
        'NOT_FOUND'
      );
    }

    if (
      !canSelectBranch(req) &&
      Number(member.BranchID) !==
        getUserBranchId(req)
    ) {
      return error(
        res,
        'You cannot delete a member from another branch',
        403,
        'BRANCH_ACCESS_DENIED'
      );
    }

    await service.delete(
      memberId,
      req.user.userId
    );

    return success(
      res,
      null,
      'Member deleted'
    );
  } catch (err) {
    console.error(
      '[members] delete error:',
      err
    );

    if (
      /cannot be deleted because/i.test(
        err.message
      )
    ) {
      return error(
        res,
        err.message,
        409,
        'DELETE_BLOCKED'
      );
    }

    return error(
      res,
      err.message,
      500
    );
  }
};

exports.payments = async (
  req,
  res
) => {
  try {
    const memberId = parseInt(
      req.params.id,
      10
    );

    const member =
      await service.get(memberId);

    if (!member) {
      return error(
        res,
        'Member not found',
        404,
        'NOT_FOUND'
      );
    }

    if (
      !canSelectBranch(req) &&
      Number(member.BranchID) !==
        getUserBranchId(req)
    ) {
      return error(
        res,
        'You cannot access this member',
        403,
        'BRANCH_ACCESS_DENIED'
      );
    }

    const result =
      await service.getPayments(
        memberId
      );

    return success(
      res,
      result,
      'Member payments'
    );
  } catch (err) {
    return error(
      res,
      err.message,
      500
    );
  }
};

exports.attendance = async (
  req,
  res
) => {
  try {
    const memberId = parseInt(
      req.params.id,
      10
    );

    const member =
      await service.get(memberId);

    if (!member) {
      return error(
        res,
        'Member not found',
        404,
        'NOT_FOUND'
      );
    }

    if (
      !canSelectBranch(req) &&
      Number(member.BranchID) !==
        getUserBranchId(req)
    ) {
      return error(
        res,
        'You cannot access this member',
        403,
        'BRANCH_ACCESS_DENIED'
      );
    }

    const result =
      await service.getAttendance(
        memberId,
        req.query.fromDate || null,
        req.query.toDate || null
      );

    return success(
      res,
      result,
      'Member attendance'
    );
  } catch (err) {
    return error(
      res,
      err.message,
      500
    );
  }
};

exports.memberships = async (
  req,
  res
) => {
  try {
    const memberId = parseInt(
      req.params.id,
      10
    );

    const member =
      await service.get(memberId);

    if (!member) {
      return error(
        res,
        'Member not found',
        404,
        'NOT_FOUND'
      );
    }

    if (
      !canSelectBranch(req) &&
      Number(member.BranchID) !==
        getUserBranchId(req)
    ) {
      return error(
        res,
        'You cannot access this member',
        403,
        'BRANCH_ACCESS_DENIED'
      );
    }

    const result =
      await service.getMemberships(
        memberId
      );

    return success(
      res,
      result,
      'Member memberships'
    );
  } catch (err) {
    return error(
      res,
      err.message,
      500
    );
  }
};

exports.progress = async (
  req,
  res
) => {
  try {
    const memberId = parseInt(
      req.params.id,
      10
    );

    const member =
      await service.get(memberId);

    if (!member) {
      return error(
        res,
        'Member not found',
        404,
        'NOT_FOUND'
      );
    }

    if (
      !canSelectBranch(req) &&
      Number(member.BranchID) !==
        getUserBranchId(req)
    ) {
      return error(
        res,
        'You cannot access this member',
        403,
        'BRANCH_ACCESS_DENIED'
      );
    }

    const result =
      await service.getProgress(
        memberId
      );

    return success(
      res,
      result,
      'Member progress'
    );
  } catch (err) {
    return error(
      res,
      err.message,
      500
    );
  }
};