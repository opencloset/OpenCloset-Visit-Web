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

const clear = key => {
  if (key) {
    sessionStorage.removeItem(key);
  } else {
    sessionStorage.clear();
  }
}

export default { save, load, clear };
