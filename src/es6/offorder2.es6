import "./lib/import-jquery";
import Mustache from "mustache/mustache";
import selectize from "./lib/selectize";
import session from "./lib/session";
import opencloset from "./lib/opencloset";

const pageId = "offorder2";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  selectize.fixSelectizeReadonly(["#offorder2PreferStyle", "#offorder2PreferColor"]);
  registerCallbackNextClick();
  registerCallbackFormInput();
  loadSession();
  updateNextButton();
  initSelectClothes();
};

const selectClothesColumns = [
  { field: "state",      align: "center", valign: "middle", checkbox: true },
  { field: "category",   align: "left",   valign: "middle" },
  { field: "count",      align: "left",   valign: "middle" },
  { field: "totalPrice", align: "right",  valign: "middle" },
];
const selectClothesData = [
  { state: false, id: "jacket", count: 0 },
  { state: false, id: "shirt",  count: 0 },
  { state: false, id: "blouse", count: 0 },
  { state: false, id: "pants",  count: 0 },
  { state: false, id: "skirt",  count: 0 },
  { state: false, id: "tie",    count: 0 },
  { state: false, id: "belt",   count: 0 },
  { state: false, id: "shoes",  count: 0 },
];

const registerSelectClothesStateCallback = () => {
  $("#offorder2SelectClothes input[type=number]").on("change", (e) => { // "propertychange change keyup paste input"
    let $target = $(e.target);
    let $tr = $target.closest("tr");
    let $table = $("#offorder2SelectClothes");
    let currentVal = parseInt($target.val(), 10);
    let index = $tr.data("index");
    let data = $table.bootstrapTable("getData");

    data[index].count = currentVal;
    $table.bootstrapTable("load", data);
    updateNextButton();
    registerSelectClothesCountCallback();
  });
}

const registerSelectClothesCountCallback = () => {
  $("#offorder2SelectClothes input[type=number]").on("change", (e) => { // "propertychange change keyup paste input"
    let $target = $(e.target);
    let $tr = $target.closest("tr");
    let $table = $("#offorder2SelectClothes");
    let currentVal = parseInt($target.val(), 10);
    let index = $tr.data("index");
    let data = $table.bootstrapTable("getData");

    data[index].count = currentVal;
    $table.bootstrapTable("load", data);
    updateTotalPrice();
    updateNextButton();
    registerSelectClothesCountCallback();
  });
}

const getTotalPrice = (data) => {
  let totalPrice = 0;
  if (!Array.isArray(data)) {
    return totalPrice;
  }
  for (let c of data.values()) {
    let data = opencloset.category(c.id);
    totalPrice += data.price * c.count;
  }
  return totalPrice;
}

const updateTotalPrice = () => {
  let $table = $("#offorder2SelectClothes");
  let data = $table.bootstrapTable("getSelections");
  let totalPrice = getTotalPrice(data);
  let $nextBtn = $("#btn-offorder2-next");
  $nextBtn.data("total-price", totalPrice);
}

const initSelectClothes = () => {
  let $selectClothes = $("#offorder2SelectClothes");
  $selectClothes.bootstrapTable({
    columns: selectClothesColumns,
    data: selectClothesData,
  });
  $selectClothes.on("check.bs.table", (e, row) => {
    updateTotalPrice();
    updateNextButton();
  });
  $selectClothes.on("uncheck.bs.table", (e, row) => {
    updateTotalPrice();
    updateNextButton();
  });
  registerSelectClothesCountCallback();
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
} else {
  domLoaded();
}

const registerCallbackNextClick = () => {
  $("#btn-offorder2-next").on("click", e => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    let $target = $(e.target);
    if ($target.hasClass("disabled")) {
      return false;
    }

    let phone = new URL(window.location.href).searchParams.get("phone");
    if (!phone) {
      return false;
    }
    session.save(phone, getFormField());

    let reqUrl = new URL($target.data("url"), window.location.origin);

    // success
    window.location = reqUrl.href;

    return false;
  });
};

const registerCallbackFormInput = () => {
  $("#offorder2PreferStyle").on("change", e => updateNextButton());
  $("#offorder2PreferColor").on("change", e => updateNextButton());
};

const loadSession = () => {
  let phone = new URL(window.location.href).searchParams.get("phone");
  if (!phone) {
    return false;
  }

  let data = session.load(phone, getFormField());
  if (data.prefer_style) {
    $("#offorder2PreferStyle")[0].selectize.setValue(data.prefer_style, false);
  }
  if (data.prefer_color) {
    $("#offorder2PreferColor")[0].selectize.setValue(data.prefer_color, false);
  }
};

const getFormField = () => {
  let formData = {
    prefer_style: $("#offorder2PreferStyle").val(),
    prefer_color: $("#offorder2PreferColor").val(),
  };

  for (let [key, value] of Object.entries(formData)) {
    if (!value) {
      continue;
    }
    formData[key] = value.trim();
  }

  return formData;
};

const validateForm = () => {
  let formData = getFormField();

  let isValid = true;
  for (let [key, value] of Object.entries(formData)) {
    if (!value) {
      isValid = false;
      break;
    }
  }

  let $table = $("#offorder2SelectClothes");
  let data = $table.bootstrapTable("getSelections");
  let totalPrice = getTotalPrice(data);
  if (totalPrice <= 0) {
    isValid = false;
  }

  return isValid;
};

const updateNextButton = () => {
  let $nextBtn = $("#btn-offorder2-next");
  let isFormValid = validateForm();
  if (isFormValid) {
    let totalPrice = parseInt($nextBtn.data("total-price"), 10);
    $nextBtn.html(Mustache.render($nextBtn.data("label2"), { totalPrice: opencloset.commify(totalPrice) })).removeClass("disabled");
  } else {
    $nextBtn.html($nextBtn.data("label1")).addClass("disabled");
  }
};

window.countFormatter = (value, row, index) => {
  let adjustedValue = value;
  if (adjustedValue < 0) {
    adjustedValue = 0;
  }
  return [
    `<input type="number" min="0" class="form-control w-8" value="${value}">`,
  ].join("");
};

window.categoryFormatter = (value, row, index) => {
  let data = opencloset.category(row.id);
  return [
    data.label,
  ].join("");
};

window.totalPriceFormatter = (value, row, index) => {
  let data = opencloset.category(row.id);
  return [
    opencloset.commify(data.price * row.count),
    "원",
  ].join("");
};
