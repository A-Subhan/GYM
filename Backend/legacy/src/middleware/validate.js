/**
 * Joi validation middleware factory.
 *
 *   router.post('/', validate(schema, 'body'), controller);
 *   router.get('/',  validate(schema, 'query'), controller);
 */
function validate(schema, source = 'body') {
  return (req, res, next) => {
    const data = req[source] || {};
    const { error: err, value } = schema.validate(data, {
      abortEarly: false,
      stripUnknown: true,
      convert: true,
    });
    if (err) {
      const details = err.details.map((d) => ({ field: d.path.join('.'), message: d.message }));
      return res.status(422).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Validation failed',
          details,
        },
      });
    }
    req[source] = value;
    next();
  };
}

module.exports = { validate };
