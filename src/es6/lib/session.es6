const save = (key, data) => {
  if (!key) {
    return;
  }

  let sessionData = JSON.parse(sessionStorage.getItem(key));
  if (!sessionData) {
    sessionData = {};
  }
  Object.assign(sessionData, data);
  sessionStorage.setItem(key, JSON.stringify(sessionData));
};

const load = key => {
  if (!key) {
    return;
  }

  let sessionData = JSON.parse(sessionStorage.getItem(key));
  if (!sessionData) {
    sessionData = {};
  }

  return sessionData;
};

export default { save, load };
