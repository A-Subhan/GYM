import { useEffect, useState } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import Button from '../../components/common/Button';
import Spinner from '../../components/common/Spinner';

export default function MemberForm() {
  const { id } = useParams();
  const isEdit = Boolean(id);

  const navigate = useNavigate();
  const toast = useToast();

  const [loading, setLoading] = useState(isEdit);
  const [saving, setSaving] = useState(false);

  const [trainers, setTrainers] = useState([]);
  const [branches, setBranches] = useState([]);
  const [membershipPlans, setMembershipPlans] = useState([]);

  const [user, setUser] = useState(null);

  const [photoFile, setPhotoFile] = useState(null);
  const [photoPreview, setPhotoPreview] = useState('');

  const [form, setForm] = useState({
    BranchID: '',
    FullName: '',
    FatherName: '',
    Gender: 'Male',
    DOB: '',
    CNIC: '',
    Mobile: '',
    WhatsApp: '',
    SameAsMobile: false,
    Email: '',
    Address: '',
    EmergencyContact: '',
    JoiningDate: new Date()
      .toISOString()
      .slice(0, 10),
    TrainerID: '',
    HeightFeet: '',
    HeightInches: '',
    Weight: '',
    MedicalNotes: '',
    Status: 'Active',
    MembershipPlanID: ''
  });

  useEffect(() => {
    try {
      const storedUser =
        localStorage.getItem('user');

      if (storedUser) {
        setUser(
          JSON.parse(storedUser)
        );
      }
    } catch {
      setUser(null);
    }
  }, []);

  const roleName = String(
    user?.roleName ||
      user?.RoleName ||
      user?.role ||
      user?.Role ||
      ''
  )
    .trim()
    .toLowerCase();

  const userBranchId =
    user?.branchId ??
    user?.BranchID ??
    user?.branchID ??
    '';

  const canSelectBranch =
    roleName === 'owner' ||
    roleName === 'admin' ||
    roleName === 'super admin' ||
    roleName === 'superadmin' ||
    user?.isOwner === true ||
    user?.isAdmin === true ||
    user?.isSuperAdmin === true;

  useEffect(() => {
    let mounted = true;

    const loadData = async () => {
      try {
        const [
          branchResponse,
          trainerResponse,
          membershipResponse
        ] = await Promise.all([
          api.get('/branches').catch(() => ({
            data: { data: [] }
          })),

          api.get('/staff/trainers').catch(() => ({
            data: { data: [] }
          })),

          api
            .get(
              '/memberships/plans?isActive=true'
            )
            .catch(() => ({
              data: { data: [] }
            }))
        ]);

        if (!mounted) return;

        setBranches(
          Array.isArray(
            branchResponse.data?.data
          )
            ? branchResponse.data.data
            : []
        );

        setTrainers(
          Array.isArray(
            trainerResponse.data?.data
          )
            ? trainerResponse.data.data
            : []
        );

        setMembershipPlans(
          Array.isArray(
            membershipResponse.data?.data
          )
            ? membershipResponse.data.data
            : []
        );

        if (isEdit) {
          const response =
            await api.get(
              `/members/${id}`
            );

          if (!mounted) return;

          const member =
            response.data.data;

          setForm({
            BranchID:
              member.BranchID ?? '',
            FullName:
              member.FullName || '',
            FatherName:
              member.FatherName || '',
            Gender:
              member.Gender || 'Male',
            DOB: member.DOB
              ? String(
                  member.DOB
                ).slice(0, 10)
              : '',
            CNIC:
              member.CNIC || '',
            Mobile:
              member.Mobile || '',
            WhatsApp:
              member.WhatsApp || '',
            SameAsMobile:
              Boolean(member.Mobile) &&
              Boolean(
                member.WhatsApp
              ) &&
              String(
                member.Mobile
              ) ===
                String(
                  member.WhatsApp
                ),
            Email:
              member.Email || '',
            Address:
              member.Address || '',
            EmergencyContact:
              member.EmergencyContact ||
              '',
            JoiningDate:
              member.JoiningDate
                ? String(
                    member.JoiningDate
                  ).slice(0, 10)
                : '',
            TrainerID:
              member.TrainerID ?? '',
            HeightFeet:
              member.HeightFeet ??
              '',
            HeightInches:
              member.HeightInches ??
              '',
            Weight:
              member.Weight ?? '',
            MedicalNotes:
              member.MedicalNotes ||
              '',
            Status:
              member.Status ||
              'Active',
            MembershipPlanID: ''
          });

          try {
            const photoResponse =
              await api.get(
                `/members/${id}/photo`,
                {
                  responseType:
                    'blob'
                }
              );

            if (
              photoResponse.data &&
              photoResponse.data.size > 0
            ) {
              const url =
                URL.createObjectURL(
                  photoResponse.data
                );

              setPhotoPreview(
                url
              );
            }
          } catch {
            setPhotoPreview('');
          }
        } else if (
          !canSelectBranch &&
          userBranchId
        ) {
          setForm(
            (current) => ({
              ...current,
              BranchID:
                userBranchId
            })
          );
        }
      } catch (err) {
        console.error(err);

        toast.error(
          'Failed to load form data'
        );
      } finally {
        if (mounted) {
          setLoading(false);
        }
      }
    };

    loadData();

    return () => {
      mounted = false;
    };
  }, [
    id,
    isEdit,
    canSelectBranch,
    userBranchId
  ]);

  const set = (key, value) => {
    setForm(
      (current) => ({
        ...current,
        [key]: value
      })
    );
  };

  const handleMobileChange = (
    value
  ) => {
    const mobile = String(value)
      .replace(/\D/g, '')
      .slice(0, 16);

    setForm(
      (current) => ({
        ...current,
        Mobile: mobile,
        WhatsApp:
          current.SameAsMobile
            ? mobile
            : current.WhatsApp
      })
    );
  };

  const handleWhatsAppChange = (
    value
  ) => {
    const whatsapp =
      String(value)
        .replace(/\D/g, '')
        .slice(0, 16);

    setForm(
      (current) => ({
        ...current,
        WhatsApp:
          whatsapp,
        SameAsMobile: false
      })
    );
  };

  const handleSameAsMobile = (
    checked
  ) => {
    setForm(
      (current) => ({
        ...current,
        SameAsMobile:
          checked,
        WhatsApp:
          checked
            ? current.Mobile
            : current.WhatsApp
      })
    );
  };

  const handlePhotoChange = (
    event
  ) => {
    const file =
      event.target.files?.[0];

    if (!file) {
      setPhotoFile(null);
      return;
    }

    if (
      !file.type.startsWith(
        'image/'
      )
    ) {
      toast.error(
        'Please select an image file'
      );

      event.target.value = '';
      return;
    }

    if (
      file.size >
      5 * 1024 * 1024
    ) {
      toast.error(
        'Photo cannot exceed 5 MB'
      );

      event.target.value = '';
      return;
    }

    setPhotoFile(file);

    const url =
      URL.createObjectURL(
        file
      );

    setPhotoPreview(url);
  };

  const validateForm = () => {
    const today =
      new Date()
        .toISOString()
        .slice(0, 10);

    if (!form.FullName.trim()) {
      toast.error(
        'Full Name is required'
      );
      return false;
    }

    if (
      form.FullName.trim().length < 3
    ) {
      toast.error(
        'Full Name must contain at least 3 characters'
      );
      return false;
    }

    if (
      form.FullName.trim().length > 50
    ) {
      toast.error(
        'Full Name cannot exceed 50 characters'
      );
      return false;
    }

    if (
      form.FatherName &&
      form.FatherName.length > 50
    ) {
      toast.error(
        'Father Name cannot exceed 50 characters'
      );
      return false;
    }

    if (form.DOB) {
      if (
        form.DOB < '1900-01-01' ||
        form.DOB > today
      ) {
        toast.error(
          'Date of Birth must be between 1900 and today'
        );
        return false;
      }
    }

    if (!form.CNIC) {
      toast.error(
        'CNIC is required'
      );
      return false;
    }

    if (
      !/^\d+$/.test(form.CNIC)
    ) {
      toast.error(
        'CNIC can contain digits only'
      );
      return false;
    }

    if (form.CNIC.length > 16) {
      toast.error(
        'CNIC cannot exceed 16 digits'
      );
      return false;
    }

    if (!form.Mobile) {
      toast.error(
        'Mobile number is required'
      );
      return false;
    }

    if (
      !/^\d+$/.test(form.Mobile)
    ) {
      toast.error(
        'Mobile number can contain digits only'
      );
      return false;
    }

    if (
      form.Mobile.length > 16
    ) {
      toast.error(
        'Mobile number cannot exceed 16 digits'
      );
      return false;
    }

    if (
      form.WhatsApp &&
      !/^\d+$/.test(
        form.WhatsApp
      )
    ) {
      toast.error(
        'WhatsApp number can contain digits only'
      );
      return false;
    }

    if (
      form.WhatsApp &&
      form.WhatsApp.length > 16
    ) {
      toast.error(
        'WhatsApp cannot exceed 16 digits'
      );
      return false;
    }

    if (
      form.Email &&
      form.Email.length > 50
    ) {
      toast.error(
        'Email cannot exceed 50 characters'
      );
      return false;
    }

    if (
      form.Email &&
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(
        form.Email
      )
    ) {
      toast.error(
        'Please enter a valid email address'
      );
      return false;
    }

    if (
      form.Address &&
      form.Address.length > 120
    ) {
      toast.error(
        'Address cannot exceed 120 characters'
      );
      return false;
    }

    if (
      form.EmergencyContact &&
      !/^\d+$/.test(
        form.EmergencyContact
      )
    ) {
      toast.error(
        'Emergency Contact can contain digits only'
      );
      return false;
    }

    if (
      form.EmergencyContact &&
      form.EmergencyContact.length > 16
    ) {
      toast.error(
        'Emergency Contact cannot exceed 16 digits'
      );
      return false;
    }

    if (!form.JoiningDate) {
      toast.error(
        'Joining Date is required'
      );
      return false;
    }

    if (form.Weight !== '') {
      const weight =
        Number(form.Weight);

      if (
        Number.isNaN(weight) ||
        weight < 0 ||
        weight > 999.9
      ) {
        toast.error(
          'Weight must be between 0 and 999.9 kg'
        );
        return false;
      }
    }

    if (
      !form.MedicalNotes.trim()
    ) {
      toast.error(
        'Medical Notes are required'
      );
      return false;
    }

    if (
      form.MedicalNotes.length >
      120
    ) {
      toast.error(
        'Medical Notes cannot exceed 120 characters'
      );
      return false;
    }

    if (!form.BranchID) {
      toast.error(
        'Please select a branch'
      );
      return false;
    }

    return true;
  };

  const handleSubmit = async (
    event
  ) => {
    event.preventDefault();

    if (!validateForm()) {
      return;
    }

    setSaving(true);

    try {
      const formData =
        new FormData();

      let branchId =
        form.BranchID;

      if (
        !canSelectBranch &&
        userBranchId
      ) {
        branchId =
          userBranchId;
      }

      formData.append(
        'BranchID',
        String(branchId)
      );

      formData.append(
        'FullName',
        form.FullName.trim()
      );

      if (form.FatherName.trim()) {
        formData.append(
          'FatherName',
          form.FatherName.trim()
        );
      }

      if (form.Gender) {
        formData.append(
          'Gender',
          form.Gender
        );
      }

      if (form.DOB) {
        formData.append(
          'DOB',
          form.DOB
        );
      }

      formData.append(
        'CNIC',
        form.CNIC
      );

      formData.append(
        'Mobile',
        form.Mobile
      );

      if (form.WhatsApp) {
        formData.append(
          'WhatsApp',
          form.WhatsApp
        );
      }

      if (form.Email.trim()) {
        formData.append(
          'Email',
          form.Email.trim()
        );
      }

      if (form.Address) {
        formData.append(
          'Address',
          form.Address
        );
      }

      if (form.EmergencyContact) {
        formData.append(
          'EmergencyContact',
          form.EmergencyContact
        );
      }

      formData.append(
        'JoiningDate',
        form.JoiningDate
      );

      if (form.TrainerID !== '') {
        formData.append(
          'TrainerID',
          String(form.TrainerID)
        );
      }

      if (form.HeightFeet !== '') {
        formData.append(
          'HeightFeet',
          String(form.HeightFeet)
        );
      }

      if (form.HeightInches !== '') {
        formData.append(
          'HeightInches',
          String(form.HeightInches)
        );
      }

      if (form.Weight !== '') {
        formData.append(
          'Weight',
          String(form.Weight)
        );
      }

      formData.append(
        'MedicalNotes',
        form.MedicalNotes.trim()
      );

      formData.append(
        'Status',
        form.Status
      );

      if (photoFile) {
        formData.append(
          'Photo',
          photoFile
        );
      }

      /* Membership plan is assigned at creation time */
      if (
        !isEdit &&
        form.MembershipPlanID !== ''
      ) {
        formData.append(
          'MembershipPlanID',
          String(
            form.MembershipPlanID
          )
        );
      }

      if (isEdit) {
        await api.put(
          `/members/${id}`,
          formData
        );

        toast.success(
          'Member updated'
        );

        navigate(
          `/members/${id}`
        );
      } else {
        const response =
          await api.post(
            '/members',
            formData
          );

        toast.success(
          'Member created'
        );

        navigate(
          `/members/${response.data.data.MemberID}`
        );
      }
    } catch (err) {
      console.error(
        'Server error:',
        err.response?.data
      );

      const message =
        err.response?.data?.error
          ?.message ||
        err.response?.data
          ?.message ||
        'Save failed';

      toast.error(message);
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <Spinner
        size="lg"
        className="mt-20"
      />
    );
  }

  return (
    <div className="max-w-3xl mx-auto space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">
          {isEdit
            ? 'Edit Member'
            : 'New Member'}
        </h1>

        <Link
          to={
            isEdit
              ? `/members/${id}`
              : '/members'
          }
        >
          <Button variant="ghost">
            Cancel
          </Button>
        </Link>
      </div>

      <form
        onSubmit={handleSubmit}
        className="card p-6 space-y-6"
      >
        <div className="grid grid-cols-1 md:grid-cols-[1fr_180px] gap-6 items-start">
          <Section title="Personal Information">
            <Input
              label="Full Name"
              value={form.FullName}
              onChange={(value) =>
                set(
                  'FullName',
                  value
                )
              }
              maxLength={50}
              required
            />

            <Input
              label="Father Name"
              value={form.FatherName}
              onChange={(value) =>
                set(
                  'FatherName',
                  value
                )
              }
              maxLength={50}
            />

            <Select
              label="Gender"
              value={form.Gender}
              onChange={(value) =>
                set(
                  'Gender',
                  value
                )
              }
              options={[
                ['Male', 'Male'],
                ['Female', 'Female'],
                ['Other', 'Other']
              ]}
            />

            <Input
              label="Date of Birth"
              type="date"
              value={form.DOB}
              onChange={(value) =>
                set(
                  'DOB',
                  value
                )
              }
              min="1900-01-01"
              max={
                new Date()
                  .toISOString()
                  .slice(0, 10)
              }
            />

            <Input
              label="CNIC"
              value={form.CNIC}
              onChange={(value) =>
                set(
                  'CNIC',
                  value
                    .replace(
                      /\D/g,
                      ''
                    )
                    .slice(0, 16)
                )
              }
              maxLength={16}
              inputMode="numeric"
              required
            />

            <Select
              label="Status"
              value={form.Status}
              onChange={(value) =>
                set(
                  'Status',
                  value
                )
              }
              options={[
                ['Active', 'Active'],
                ['Inactive', 'Inactive'],
                ['Frozen', 'Frozen'],
                ['Expired', 'Expired']
              ]}
            />
          </Section>

          <div>
            <label className="label">
              Member Photo
            </label>

            <div className="w-full aspect-square rounded-lg border border-slate-300 dark:border-slate-700 overflow-hidden bg-slate-100 dark:bg-slate-800 flex items-center justify-center mb-3">
              {photoPreview ? (
                <img
                  src={photoPreview}
                  alt="Member"
                  className="w-full h-full object-cover"
                />
              ) : (
                <span className="text-sm text-slate-500">
                  No photo
                </span>
              )}
            </div>

            <input
              type="file"
              accept="image/*"
              onChange={
                handlePhotoChange
              }
              className="input"
            />

            <p className="text-xs text-slate-500 mt-2">
              Optional. Maximum 5 MB.
            </p>
          </div>
        </div>

        <Section title="Contact">
          <Input
            label="Mobile"
            value={form.Mobile}
            onChange={
              handleMobileChange
            }
            maxLength={16}
            inputMode="numeric"
            required
          />

          <div>
            <Input
              label="WhatsApp"
              value={form.WhatsApp}
              onChange={
                handleWhatsAppChange
              }
              maxLength={16}
              inputMode="numeric"
            />

            <label className="mt-2 flex items-center gap-2 text-sm text-slate-600 dark:text-slate-300">
              <input
                type="checkbox"
                checked={
                  form.SameAsMobile
                }
                onChange={(event) =>
                  handleSameAsMobile(
                    event.target
                      .checked
                  )
                }
              />

              Same as mobile number
            </label>
          </div>

          <Input
            label="Email"
            type="email"
            value={form.Email}
            onChange={(value) =>
              set(
                'Email',
                value
              )
            }
            maxLength={50}
          />

          <Input
            label="Emergency Contact"
            value={
              form.EmergencyContact
            }
            onChange={(value) =>
              set(
                'EmergencyContact',
                value
                  .replace(
                    /\D/g,
                    ''
                  )
                  .slice(0, 16)
              )
            }
            maxLength={16}
            inputMode="numeric"
          />

          <Input
            label="Address"
            value={form.Address}
            onChange={(value) =>
              set(
                'Address',
                value
              )
            }
            maxLength={120}
            span={2}
          />
        </Section>

        <Section title="Membership & Trainer">
          <Select
            label="Branch"
            value={form.BranchID}
            onChange={(value) =>
              set(
                'BranchID',
                value
              )
            }
            options={branches
              .filter(
                (branch) =>
                  !branch.IsDeleted &&
                  branch.IsActive
              )
              .map((branch) => [
                branch.BranchID,
                `${branch.Code} — ${branch.Name}`
              ])}
            placeholder="Select branch"
            disabled={
              !canSelectBranch
            }
          />

          <Select
            label="Trainer"
            value={form.TrainerID}
            onChange={(value) =>
              set(
                'TrainerID',
                value
              )
            }
            options={trainers.map(
              (trainer) => [
                trainer.TrainerID,
                trainer.StaffName ||
                  trainer.FullName ||
                  `Trainer #${trainer.TrainerID}`
              ]
            )}
            placeholder="No trainer"
          />

          <Input
            label="Joining Date"
            type="date"
            value={
              form.JoiningDate
            }
            onChange={(value) =>
              set(
                'JoiningDate',
                value
              )
            }
            required
          />

          <Select
            label="Membership Plan"
            value={
              form.MembershipPlanID
            }
            onChange={(value) =>
              set(
                'MembershipPlanID',
                value
              )
            }
            options={membershipPlans.map(
              (plan) => [
                plan.MembershipPlanID ??
                  plan.PlanID ??
                  plan.ID,
                plan.Name ??
                  plan.PlanName ??
                  `Plan #${
                    plan.MembershipPlanID ??
                    plan.PlanID ??
                    plan.ID
                  }`
              ]
            )}
            placeholder="No membership"
          />

          <Input
            label="Height (feet)"
            type="number"
            value={
              form.HeightFeet
            }
            onChange={(value) =>
              set(
                'HeightFeet',
                value
              )
            }
            min={1}
            max={8}
            step="1"
            placeholder="e.g. 5"
          />

          <Input
            label="Height (inches)"
            type="number"
            value={
              form.HeightInches
            }
            onChange={(value) =>
              set(
                'HeightInches',
                value
              )
            }
            min={0}
            max={11}
            step="1"
            placeholder="e.g. 6"
          />

          <Input
            label="Weight (kg)"
            type="number"
            value={form.Weight}
            onChange={(value) =>
              set(
                'Weight',
                value
              )
            }
            min={0}
            max={999.9}
            step="0.1"
          />

          <Input
            label="Medical Notes"
            value={
              form.MedicalNotes
            }
            onChange={(value) =>
              set(
                'MedicalNotes',
                value
              )
            }
            maxLength={120}
            span={2}
            required
          />
        </Section>

        <div className="flex justify-end gap-2 pt-2">
          <Link
            to={
              isEdit
                ? `/members/${id}`
                : '/members'
            }
          >
            <Button
              type="button"
              variant="secondary"
            >
              Cancel
            </Button>
          </Link>

          <Button
            type="submit"
            disabled={saving}
          >
            {saving
              ? 'Saving…'
              : isEdit
                ? 'Update Member'
                : 'Create Member'}
          </Button>
        </div>
      </form>
    </div>
  );
}

function Section({
  title,
  children
}) {
  return (
    <div>
      <h3 className="text-sm font-semibold text-slate-700 dark:text-slate-300 mb-3 uppercase tracking-wide">
        {title}
      </h3>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {children}
      </div>
    </div>
  );
}

function Input({
  label,
  value,
  onChange,
  type = 'text',
  required,
  span = 1,
  maxLength,
  inputMode,
  min,
  max,
  step,
  placeholder
}) {
  return (
    <div
      className={
        span === 2
          ? 'md:col-span-2'
          : ''
      }
    >
      <label className="label">
        {label}

        {required && (
          <span className="text-red-500">
            {' '}*
          </span>
        )}
      </label>

      <input
        type={type}
        value={value}
        onChange={(event) =>
          onChange(
            event.target.value
          )
        }
        className="input"
        required={required}
        maxLength={maxLength}
        inputMode={inputMode}
        min={min}
        max={max}
        step={step}
        placeholder={placeholder}
      />
    </div>
  );
}

function Select({
  label,
  value,
  onChange,
  options,
  placeholder,
  span = 1,
  disabled = false
}) {
  return (
    <div
      className={
        span === 2
          ? 'md:col-span-2'
          : ''
      }
    >
      <label className="label">
        {label}
      </label>

      <select
        value={value}
        onChange={(event) =>
          onChange(
            event.target.value
          )
        }
        className="input"
        disabled={disabled}
      >
        {placeholder && (
          <option value="">
            {placeholder}
          </option>
        )}

        {options.map(
          ([value, label]) => (
            <option
              key={value}
              value={value}
            >
              {label}
            </option>
          )
        )}
      </select>
    </div>
  );
}